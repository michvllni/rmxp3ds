// SPDX-License-Identifier: GPL-3.0-or-later
// M1: CRuby on the New 3DS. Initialises the Ruby VM like mkxp-z (binding/binding-mri.cpp), runs
// rgss_stubs.rb and a test/benchmark script, and reports in the self-reporting test format:
//   sdmc:/rmxp3ds/test/rubybench.txt          "RMXP3DS_TEST rubybench PASS|FAIL ..."
//   sdmc:/rmxp3ds/test/rubybench-results.txt  full output (checks, timings, GC stats, errors)
// Both are also shown on the top screen and written to stderr (3dslink -s).
// Script lookup: sdmc:/rmxp3ds/test/<name>.rb first (run scripts from SD without rebuilding),
// then romfs:/<name>.rb. sdmc:/rmxp3ds/test/autoexit: exit a few seconds after reporting.
#include <3ds.h>
#include <malloc.h>
#include <pthread.h>
#include <time.h>
#include <ruby.h>
#include <ruby/encoding.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Main thread stack (libctru default: 32 KiB). CRuby's C recursion needs far more.
u32 __stacksize__ = 1024 * 1024;

#define TEST_DIR "sdmc:/rmxp3ds/test"
#define AUTOEXIT_FRAMES 180
#define SOC_BUFFER_SIZE 0x100000
#define SOC_ALIGN 0x1000

static PrintConsole top_console;

// Appends a progress marker to TEST_DIR/rubybench-stage.txt (survives a crash: closed each time).
static void stage(const char *what) {
	mkdir("sdmc:/rmxp3ds", 0777);
	mkdir(TEST_DIR, 0777);
	FILE *f = fopen(TEST_DIR "/rubybench-stage.txt", "a");
	if (f == NULL) return;
	fprintf(f, "%llu %s\n", (unsigned long long)osGetTime(), what);
	fclose(f);
}

// Connects stderr to the 3dslink host if started by 3dslink. Returns the socket fd or -1.
static int connect_3dslink(u32 **soc_buffer) {
	if (__3dslink_host.s_addr == 0) return -1;
	*soc_buffer = memalign(SOC_ALIGN, SOC_BUFFER_SIZE);
	if (*soc_buffer == NULL) return -1;
	if (R_FAILED(socInit(*soc_buffer, SOC_BUFFER_SIZE))) {
		free(*soc_buffer);
		*soc_buffer = NULL;
		return -1;
	}
	return link3dsStdioForDebug();
}

// Writes text to TEST_DIR/name. Returns 0 on success.
static int write_test_file(const char *name, const char *text) {
	char path[96];
	mkdir("sdmc:/rmxp3ds", 0777);
	mkdir(TEST_DIR, 0777);
	snprintf(path, sizeof path, "%s/%s", TEST_DIR, name);
	FILE *f = fopen(path, "w");
	if (f == NULL) return -1;
	int ok = fputs(text, f) >= 0;
	return (fclose(f) == 0 && ok) ? 0 : -1;
}

// Returns the script path for name: TEST_DIR/name if it exists, else romfs:/name.
static const char *script_path(const char *name, char *buf, size_t size) {
	snprintf(buf, size, "%s/%s", TEST_DIR, name);
	if (access(buf, F_OK) == 0) return buf;
	snprintf(buf, size, "romfs:/%s", name);
	return buf;
}

// rb_protect body: evaluates the file at path (a Ruby String) at top level, returns the value.
static VALUE eval_file(VALUE path) {
	VALUE src = rb_funcall(rb_cFile, rb_intern("read"), 1, path);
	return rb_funcall(rb_mKernel, rb_intern("eval"), 4, src, rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING")),
	                  path, INT2FIX(1));
}

// --- Coroutine VFP check -------------------------------------------------------------------
// Under the hard-float AAPCS, d8-d15 are callee-saved, so a Fiber switch must preserve them
// (runtime/3ds/ruby/patches/0004). The fiber holds 7.0 in d8 while it yields; the caller holds
// 3.0 in d8 across rb_fiber_resume and must still see 3.0 afterwards.
static VALUE vfp_fiber_body(RB_BLOCK_CALL_FUNC_ARGLIST(arg, callback)) {
	(void)arg;
	(void)callback;
	register double d8 __asm__("d8") = 7.0;
	__asm__ volatile("" : "+w"(d8));
	rb_fiber_yield(0, NULL);
	__asm__ volatile("" : "+w"(d8));
	return DBL2NUM(d8);
}

// rb_protect body: returns Qtrue if d8 survives a Fiber switch. Explicit asm instead of a
// register variable: d8 must be read right after the first resume, before the fiber finishes
// (its epilogue restores d8 and would hide the bug).
static VALUE check_coroutine_vfp(VALUE unused) {
	(void)unused;
	VALUE fiber = rb_fiber_new(vfp_fiber_body, Qnil);
	const double mark = 3.0;
	double got;
	__asm__ volatile("vmov.f64 d8, %P0" : : "w"(mark) : "d8");
	rb_fiber_resume(fiber, 0, NULL);
	__asm__ volatile("vmov.f64 %P0, d8" : "=w"(got));
	volatile double mine = got;
	VALUE theirs = rb_fiber_resume(fiber, 0, NULL);
	return (mine == mark && RFLOAT_VALUE(theirs) == 7.0) ? Qtrue : Qfalse;
}

// --- Native pthread check (below Ruby's GVL) -------------------------------------------------
// libctru maps pthread_create to threadCreate(prio 0x3F, core 0): the new thread only runs while
// the creator blocks. Checks that a pthread runs while main waits in pthread_cond_timedwait,
// with the clock Ruby uses (CLOCK_MONOTONIC via pthread_condattr_setclock, if available).
static pthread_mutex_t pt_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t pt_cond;
static volatile int pt_ran;

static void *pt_body(void *arg) {
	(void)arg;
	pthread_mutex_lock(&pt_lock);
	pt_ran = 1;
	pthread_cond_signal(&pt_cond);
	pthread_mutex_unlock(&pt_lock);
	return NULL;
}

// Returns a description: "ok (...)" or "FAILED (...)".
static const char *check_native_pthread(char *buf, size_t size) {
	pthread_condattr_t ca;
	pthread_condattr_init(&ca);
	int setclock = pthread_condattr_setclock(&ca, CLOCK_MONOTONIC);
	pthread_cond_init(&pt_cond, &ca);
	pthread_t t;
	int rc = pthread_create(&t, NULL, pt_body, NULL);
	if (rc != 0) {
		snprintf(buf, size, "FAILED (pthread_create %d)", rc);
		return buf;
	}
	struct timespec deadline;
	clock_gettime(setclock == 0 ? CLOCK_MONOTONIC : CLOCK_REALTIME, &deadline);
	deadline.tv_sec += 2;
	int wait_rc = 0;
	u64 t0 = osGetTime();
	pthread_mutex_lock(&pt_lock);
	while (!pt_ran && wait_rc == 0) wait_rc = pthread_cond_timedwait(&pt_cond, &pt_lock, &deadline);
	pthread_mutex_unlock(&pt_lock);
	u64 waited = osGetTime() - t0;
	pthread_join(t, NULL);
	snprintf(buf, size, "%s (setclock=%d wait_rc=%d waited_ms=%llu)", pt_ran ? "ok" : "FAILED", setclock, wait_rc,
	         (unsigned long long)waited);
	return buf;
}

// Recurses with ~1 KiB frames until ruby_stack_check() reports an imminent overflow; returns
// the depth (~KiB of stack below this point) or limit if it never fires. Checks that CRuby knows
// the main stack size (runtime/3ds/ruby/patches/0001); without it the limit is never reached.
static int __attribute__((noinline)) stack_probe(int depth, int limit) {
	volatile char frame[1000];
	frame[0] = (char)depth;
	if (depth >= limit || ruby_stack_check()) return depth + frame[0] - (char)depth;
	int r = stack_probe(depth + 1, limit); // not a tail call: GCC would turn it into a loop
	frame[1] = (char)r;
	return r;
}

// rb_protect body: returns the pending exception's full message (no ANSI colours).
static VALUE error_message(VALUE err) {
	VALUE opts = rb_hash_new();
	rb_hash_aset(opts, ID2SYM(rb_intern("highlight")), Qfalse);
	return rb_funcall(err, rb_intern("full_message"), 1, opts);
}

// Runs one script; on success stores its value (if a String) in *out. Returns 0 on success, or
// stores the error text in *out and returns -1.
static int run_script(const char *name, VALUE *out) {
	char buf[96];
	int state = 0;
	VALUE path = rb_str_new_cstr(script_path(name, buf, sizeof buf));
	VALUE v = rb_protect(eval_file, path, &state);
	if (state) {
		VALUE err = rb_errinfo();
		rb_set_errinfo(Qnil);
		int st2 = 0;
		VALUE msg = rb_protect(error_message, err, &st2);
		*out = st2 ? rb_sprintf("%s: error (state %d), message unavailable\n", buf, state)
		           : rb_sprintf("%s: %" PRIsVALUE "\n", buf, msg);
		return -1;
	}
	*out = RB_TYPE_P(v, T_STRING) ? v : rb_str_new_cstr("");
	return 0;
}

int main(void) {
	gfxInitDefault();
	consoleInit(GFX_TOP, &top_console);
	Result romfs_rc = romfsInit();
	u32 *soc_buffer = NULL;
	int link_fd = connect_3dslink(&soc_buffer);
	if (link_fd < 0) {
		// Keep Ruby's own diagnostics ([BUG] reports, warnings) when no 3dslink host listens.
		mkdir("sdmc:/rmxp3ds", 0777);
		mkdir(TEST_DIR, 0777);
		if (freopen(TEST_DIR "/rubybench-stderr.txt", "w", stderr) != NULL) setvbuf(stderr, NULL, _IONBF, 0);
	}
	bool is_new3ds = false;
	APT_CheckNew3DS(&is_new3ds);
	osSetSpeedupEnable(true); // New 3DS: 804 MHz + L2 cache; no-op on Old 3DS

	printf("rmxp3ds M1: CRuby bench\n");
	if (R_FAILED(romfs_rc)) printf("romfsInit failed: %08lx\n", (unsigned long)romfs_rc);

	{
		char msg[96];
		int probe;
		snprintf(msg, sizeof msg, "start sp~%p stacksize=%lu", (void *)&probe, (unsigned long)__stacksize__);
		stage(msg);
	}
	u64 t0 = osGetTime();
	int argc = 0;
	char **argv = NULL;
	ruby_sysinit(&argc, &argv);
	stage("ruby_sysinit done");
	int status = 0;
	VALUE detail = Qnil;
	u64 init_ms = 0;
	{
		RUBY_INIT_STACK;
		stage("ruby_init");
		ruby_init();
		stage("ruby_options");
		char *ruby_args[] = {"rmxp3ds", "-e", ""};
		void *node = ruby_options(3, ruby_args);
		int state = 0;
		if (!ruby_executable_node(node, &state) || (state = ruby_exec_node(node)) != 0) {
			printf("ruby_options failed (state %d)\n", state);
			status = -1;
		} else {
			rb_enc_set_default_internal(rb_enc_from_encoding(rb_utf8_encoding()));
			rb_enc_set_default_external(rb_enc_from_encoding(rb_utf8_encoding()));
			init_ms = osGetTime() - t0;
			stage("scripts");
			VALUE out = Qnil;
			// Native checks first; their lines prefix the script output.
			const int probe_limit = (int)(__stacksize__ / 1024) - 64;
			int fires_kb = stack_probe(0, probe_limit);
			int vstate = 0;
			VALUE vfp_ok = rb_protect(check_coroutine_vfp, Qnil, &vstate);
			if (vstate) rb_set_errinfo(Qnil);
			char ptbuf[96];
			const char *pt = check_native_pthread(ptbuf, sizeof ptbuf);
			if (strncmp(pt, "ok", 2) != 0) status = -1;
			VALUE native = rb_sprintf("check native_pthread %s\n"
			                          "check native_stack_limit %s (fires at ~%d KiB of %lu)\n"
			                          "check coroutine_vfp %s\n", pt,
			                          fires_kb < probe_limit ? "ok" : "FAILED", fires_kb,
			                          (unsigned long)(__stacksize__ / 1024),
			                          (!vstate && vfp_ok == Qtrue) ? "ok" : "FAILED (d8 not preserved across Fiber switch)");
			if (fires_kb >= probe_limit || vstate || vfp_ok != Qtrue) status = -1;
			if (status == 0) status = run_script("rgss_stubs.rb", &out);
			if (status == 0) status = run_script("bench.rb", &out);
			out = rb_str_plus(native, NIL_P(out) ? rb_str_new_cstr("") : out);
			detail = out;
			rb_gc_register_address(&detail);
		}
	}

	stage("report");
	u64 total_ms = osGetTime() - t0;
	struct mallinfo mi = mallinfo();
	const char *detail_c = NIL_P(detail) ? "" : StringValueCStr(detail);
	char line[224];
	snprintf(line, sizeof line,
	         "RMXP3DS_TEST rubybench %s init_ms=%llu total_ms=%llu new3ds=%d heap_kb=%lu malloc_arena_kb=%lu "
	         "malloc_used_kb=%lu\n",
	         status == 0 ? "PASS" : "FAIL", (unsigned long long)init_ms, (unsigned long long)total_ms,
	         is_new3ds ? 1 : 0, (unsigned long)(envGetHeapSize() / 1024), (unsigned long)(mi.arena / 1024),
	         (unsigned long)(mi.uordblks / 1024));

	char *results = malloc(strlen(line) + strlen(detail_c) + 1);
	if (results != NULL) {
		strcpy(results, line);
		strcat(results, detail_c);
		write_test_file("rubybench-results.txt", results);
		free(results);
	}
	write_test_file("rubybench.txt", line);
	printf("%s%s", line, detail_c);
	if (link_fd >= 0) {
		fputs(line, stderr);
		fputs(detail_c, stderr);
	}

	bool autoexit = access(TEST_DIR "/autoexit", F_OK) == 0;
	u32 frames = 0;
	while (aptMainLoop()) {
		hidScanInput();
		if (hidKeysDown() & KEY_START) break;
		if (autoexit && ++frames >= AUTOEXIT_FRAMES) break;
		gfxFlushBuffers();
		gfxSwapBuffers();
		gspWaitForVBlank();
	}

	ruby_cleanup(0);
	if (link_fd >= 0) close(link_fd);
	if (soc_buffer != NULL) {
		socExit();
		free(soc_buffer);
	}
	romfsExit();
	gfxExit();
	return 0;
}
