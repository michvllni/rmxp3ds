// SPDX-License-Identifier: GPL-3.0-or-later
// M3 check of the 3DS SDL2 utility libraries (runtime/3ds/deps): SDL2 without video, SDL2_image,
// SDL2_ttf. These are what mkxp-z's Bitmap, Font and file code use on the 3DS; video stays with
// citro3d. Checks, each one result line:
//   png      IMG_Load of an 8x8 RGBA PNG from romfs, every pixel against the generator's formula
//   blit     alpha blend of that image onto an opaque surface (SDL_FillRect + SDL_BlitSurface)
//   ttf      TTF_OpenFont (Liberation Sans from the runtime's assets), size + blended rendering
//   thread   SDL_CreateThreadWithStackSize with 1 MiB, recursing through ~768 KiB of it
//   rwops    SDL_RWFromFile write + read back on sdmc:/
// Self-reporting test mode (AGENTS.md): RMXP3DS_TEST sdlcheck PASS|FAIL in
// sdmc:/rmxp3ds/test/sdlcheck.txt, details in sdlcheck-results.txt; autoexit as in tools/hello.
#define SDL_MAIN_HANDLED
#include <3ds.h>
#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>
#include <malloc.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define TEST_DIR "sdmc:/rmxp3ds/test"
#define AUTOEXIT_DELAY 180
#define SOC_BUFFER_SIZE 0x100000
#define SOC_ALIGN 0x1000
#define THREAD_STACK (1024 * 1024)
#define THREAD_DEPTH 768 // ~1 KiB frames

static char details[4096];
static size_t details_len;
static int failures;

// Appends one formatted line to the details and counts a failure if ok is false.
static void report(int ok, const char *fmt, ...) {
	char msg[256];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(msg, sizeof msg, fmt, ap);
	va_end(ap);
	if (!ok) failures++;
	int n = snprintf(details + details_len, sizeof details - details_len, "check %s %s\n", msg,
	                 ok ? "ok" : "FAILED");
	if (n > 0 && (size_t)n < sizeof details - details_len) details_len += (size_t)n;
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

// Connects stderr to the 3dslink host if started by 3dslink. Returns the fd or -1.
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

// Expected pixel of the test image (tools/sdlcheck/make-png.rb).
static void expected_pixel(int x, int y, Uint8 px[4]) {
	px[0] = (Uint8)(x * 32);
	px[1] = (Uint8)(y * 32);
	px[2] = (Uint8)((x * y * 4) & 255);
	px[3] = ((x + y) & 1) ? 128 : 255;
}

// Returns the RGBA bytes of pixel (x, y) of an SDL_PIXELFORMAT_RGBA32 surface.
static const Uint8 *pixel_at(SDL_Surface *s, int x, int y) {
	return (const Uint8 *)s->pixels + y * s->pitch + x * 4;
}

// png + blit checks. Returns nothing; reports each check.
static void check_image(void) {
	SDL_Surface *loaded = IMG_Load("romfs:/check.png");
	if (loaded == NULL) {
		report(0, "png (IMG_Load: %s)", IMG_GetError());
		report(0, "blit (no image)");
		return;
	}
	SDL_Surface *img = SDL_ConvertSurfaceFormat(loaded, SDL_PIXELFORMAT_RGBA32, 0);
	SDL_FreeSurface(loaded);
	if (img == NULL) {
		report(0, "png (convert: %s)", SDL_GetError());
		report(0, "blit (no image)");
		return;
	}
	if (img->w != 8 || img->h != 8) {
		report(0, "png (%dx%d, expected 8x8)", img->w, img->h);
		report(0, "blit (no image)");
		SDL_FreeSurface(img);
		return;
	}
	int bad = 0;
	for (int y = 0; y < 8; y++) {
		for (int x = 0; x < 8; x++) {
			Uint8 want[4];
			expected_pixel(x, y, want);
			if (memcmp(pixel_at(img, x, y), want, 4) != 0) bad++;
		}
	}
	report(bad == 0, "png (8x8, %d of 64 pixels differ)", bad);

	// Blend onto opaque blue: dst = src * a + dst * (1 - a), SDL rounds within 2 per channel.
	SDL_Surface *dst = SDL_CreateRGBSurfaceWithFormat(0, 16, 16, 32, SDL_PIXELFORMAT_RGBA32);
	int maxdiff = 999;
	if (dst != NULL) {
		SDL_FillRect(dst, NULL, SDL_MapRGBA(dst->format, 0, 0, 255, 255));
		SDL_SetSurfaceBlendMode(img, SDL_BLENDMODE_BLEND);
		SDL_Rect at = {5, 7, 8, 8};
		SDL_BlitSurface(img, NULL, dst, &at);
		maxdiff = 0;
		for (int y = 0; y < 8; y++) {
			for (int x = 0; x < 8; x++) {
				Uint8 s[4];
				expected_pixel(x, y, s);
				const Uint8 base[3] = {0, 0, 255};
				const Uint8 *d = pixel_at(dst, x + 5, y + 7);
				for (int c = 0; c < 3; c++) {
					int want = (s[c] * s[3] + base[c] * (255 - s[3]) + 127) / 255;
					int diff = abs(d[c] - want);
					if (diff > maxdiff) maxdiff = diff;
				}
			}
		}
		// outside the blit stays blue
		const Uint8 *o = pixel_at(dst, 0, 0);
		if (o[0] != 0 || o[1] != 0 || o[2] != 255 || o[3] != 255) maxdiff = 999;
		SDL_FreeSurface(dst);
	}
	report(maxdiff <= 2, "blit (max channel difference %d)", maxdiff);
	SDL_FreeSurface(img);
}

// ttf check: opens the runtime's bundled font, measures and renders a string with non-ASCII text.
static void check_ttf(void) {
	if (TTF_Init() != 0) {
		report(0, "ttf (TTF_Init: %s)", TTF_GetError());
		return;
	}
	TTF_Font *font = TTF_OpenFont("romfs:/liberation.ttf", 22);
	if (font == NULL) {
		report(0, "ttf (open: %s)", TTF_GetError());
		TTF_Quit();
		return;
	}
	const char *text = "rmxp3ds \xc3\x84\xc3\xb6 123";
	// The font must really have the non-ASCII glyphs (a missing one renders as .notdef, still inked).
	int glyphs = TTF_GlyphIsProvided32(font, 0xC4) && TTF_GlyphIsProvided32(font, 0xF6);
	int w = 0, h = 0;
	TTF_SizeUTF8(font, text, &w, &h);
	SDL_Color white = {255, 255, 255, 255};
	SDL_Surface *s = TTF_RenderUTF8_Blended(font, text, white);
	long inked = 0;
	int sw = 0, sh = 0;
	if (s != NULL) {
		SDL_Surface *c = SDL_ConvertSurfaceFormat(s, SDL_PIXELFORMAT_RGBA32, 0);
		if (c != NULL) {
			sw = c->w;
			sh = c->h;
			for (int y = 0; y < c->h; y++)
				for (int x = 0; x < c->w; x++)
					if (pixel_at(c, x, y)[3] > 0) inked++;
			SDL_FreeSurface(c);
		}
		SDL_FreeSurface(s);
	}
	// Plausible for 15 glyphs at 22 px; exact metrics differ by FreeType version and hinting.
	int ok = glyphs && w > 100 && w < 300 && h > 15 && h < 40 && sw == w && sh == h && inked > 200;
	report(ok, "ttf (glyphs %s, size %dx%d, rendered %dx%d, %ld inked pixels)", glyphs ? "yes" : "MISSING", w, h,
	       sw, sh, inked);
	TTF_CloseFont(font);
	TTF_Quit();
}

// Recurses with ~1 KiB frames; not a tail call (the volatile store after the call).
static int __attribute__((noinline)) deep(int depth) {
	volatile char frame[1000];
	frame[0] = (char)depth;
	if (depth == 0) return frame[0];
	int r = deep(depth - 1) + 1;
	frame[1] = (char)r;
	return r;
}

static size_t heap_before_thread;
static long thread_heap_kb;

// Thread body: records how much the heap grew for this thread (libctru allocates the stack with
// memalign, no guard page: an ignored stack size would not crash, so the size is checked
// directly), then returns the recursion depth reached.
static int thread_body(void *unused) {
	(void)unused;
	thread_heap_kb = (long)(mallinfo().uordblks - heap_before_thread) / 1024;
	return deep(THREAD_DEPTH);
}

// thread check: a thread with a 1 MiB stack (heap grew by at least that) runs ~768 KiB deep.
static void check_thread(void) {
	heap_before_thread = mallinfo().uordblks;
	SDL_Thread *t = SDL_CreateThreadWithStackSize(thread_body, "deep", THREAD_STACK, NULL);
	if (t == NULL) {
		report(0, "thread (create: %s)", SDL_GetError());
		return;
	}
	int result = -1;
	SDL_WaitThread(t, &result);
	report(result == THREAD_DEPTH && thread_heap_kb >= THREAD_STACK / 1024,
	       "thread (heap +%ld KiB for a 1 MiB stack, depth %d of %d)", thread_heap_kb, result, THREAD_DEPTH);
}

// rwops check: writes and reads back a file on the SD card.
static void check_rwops(void) {
	const char *path = TEST_DIR "/sdlcheck.tmp";
	const char data[] = "rmxp3ds rwops";
	char back[sizeof data] = {0};
	size_t wrote = 0, read = 0;
	SDL_RWops *rw = SDL_RWFromFile(path, "wb");
	if (rw != NULL) {
		wrote = SDL_RWwrite(rw, data, 1, sizeof data);
		SDL_RWclose(rw);
	}
	rw = SDL_RWFromFile(path, "rb");
	if (rw != NULL) {
		read = SDL_RWread(rw, back, 1, sizeof back);
		SDL_RWclose(rw);
	}
	remove(path);
	report(wrote == sizeof data && read == sizeof data && memcmp(data, back, sizeof data) == 0,
	       "rwops (wrote %u, read %u)", (unsigned)wrote, (unsigned)read);
}

int main(void) {
	gfxInitDefault();
	PrintConsole top;
	consoleInit(GFX_TOP, &top);
	Result romfs_rc = romfsInit();
	u32 *soc_buffer = NULL;
	int link_fd = connect_3dslink(&soc_buffer);
	bool is_new3ds = false;
	APT_CheckNew3DS(&is_new3ds);

	mkdir("sdmc:/rmxp3ds", 0777); // rwops writes there before any result file
	mkdir(TEST_DIR, 0777);
	SDL_SetMainReady();
	if (SDL_Init(0) != 0) report(0, "sdl_init (%s)", SDL_GetError());
	if (R_FAILED(romfs_rc)) report(0, "romfs (romfsInit %08lx)", (unsigned long)romfs_rc);
	check_image();
	check_ttf();
	check_thread();
	check_rwops();
	SDL_version v;
	SDL_GetVersion(&v);

	char line[160];
	snprintf(line, sizeof line, "RMXP3DS_TEST sdlcheck %s failures=%d sdl=%d.%d.%d new3ds=%d\n",
	         failures == 0 ? "PASS" : "FAIL", failures, v.major, v.minor, v.patch, is_new3ds ? 1 : 0);
	char all[sizeof line + sizeof details];
	snprintf(all, sizeof all, "%s%s", line, details);
	write_test_file("sdlcheck-results.txt", all);
	write_test_file("sdlcheck.txt", line);
	fputs(all, stdout);
	if (link_fd >= 0) fputs(all, stderr);
	printf("Press START to exit.\n");

	bool autoexit = access(TEST_DIR "/autoexit", F_OK) == 0;
	u32 frame = 0;
	while (aptMainLoop()) {
		hidScanInput();
		if (hidKeysDown() & KEY_START) break;
		if (autoexit && ++frame >= AUTOEXIT_DELAY) break;
		gfxFlushBuffers();
		gfxSwapBuffers();
		gspWaitForVBlank();
	}

	SDL_Quit();
	if (link_fd >= 0) close(link_fd);
	if (soc_buffer != NULL) {
		socExit();
		free(soc_buffer);
	}
	romfsExit();
	gfxExit();
	return 0;
}
