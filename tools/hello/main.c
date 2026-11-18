// SPDX-License-Identifier: GPL-3.0-or-later
// M0 hello world for rmxp3ds: shows a text console on the top screen and reports a test result.
//
// Self-reporting test mode (the pattern the runtime's test mode follows, PLAN §6.2):
// after RESULT_FRAME frames it writes one result line to sdmc:/rmxp3ds/test/hello.txt and to
// stdout. Started via `3dslink -s`, stdout goes to the PC; in Azahar the file lands in the virtual
// SD card. Without 3dslink the line is shown on the top screen instead. The app then waits for
// START, or, when sdmc:/rmxp3ds/test/autoexit exists (unattended runs), exits AUTOEXIT_DELAY
// frames later (time for a screenshot of the final state).
#include <3ds.h>
#include <arpa/inet.h>
#include <malloc.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#define RESULT_FRAME 60
#define AUTOEXIT_DELAY 180
#define SOC_BUFFER_SIZE 0x100000
#define SOC_ALIGN 0x1000

// Connects stdout/stderr to the 3dslink host if the app was started by 3dslink.
// Returns the socket fd, or -1 if not started by 3dslink or on failure.
static int connect_3dslink(u32 **soc_buffer) {
	if (__3dslink_host.s_addr == 0) return -1;
	*soc_buffer = memalign(SOC_ALIGN, SOC_BUFFER_SIZE);
	if (*soc_buffer == NULL) return -1;
	if (R_FAILED(socInit(*soc_buffer, SOC_BUFFER_SIZE))) {
		free(*soc_buffer);
		*soc_buffer = NULL;
		return -1;
	}
	return link3dsStdio();
}

// Writes the test result line to sdmc:/rmxp3ds/test/hello.txt. Returns 0 on success.
static int write_result(const char *line) {
	mkdir("sdmc:/rmxp3ds", 0777);
	mkdir("sdmc:/rmxp3ds/test", 0777);
	FILE *f = fopen("sdmc:/rmxp3ds/test/hello.txt", "w");
	if (f == NULL) return -1;
	int ok = fputs(line, f) >= 0;
	return (fclose(f) == 0 && ok) ? 0 : -1;
}

int main(void) {
	gfxInitDefault();
	PrintConsole top;
	consoleInit(GFX_TOP, &top);

	u32 *soc_buffer = NULL;
	int link_fd = connect_3dslink(&soc_buffer);

	bool is_new3ds = false;
	APT_CheckNew3DS(&is_new3ds);
	printf("\x1b[2;2Hrmxp3ds hello (M0)\n");
	printf("\x1b[4;2Hmodel: %s\n", is_new3ds ? "New 3DS" : "Old 3DS");
	printf("\x1b[6;2HPress START to exit.\n");

	bool autoexit = access("sdmc:/rmxp3ds/test/autoexit", F_OK) == 0;
	u32 frame = 0;
	bool reported = false;
	while (aptMainLoop()) {
		hidScanInput();
		if (hidKeysDown() & KEY_START) break;

		if (!reported && ++frame >= RESULT_FRAME) {
			char line[96];
			snprintf(line, sizeof line, "RMXP3DS_TEST hello PASS frames=%lu new3ds=%d\n",
			         (unsigned long)frame, is_new3ds ? 1 : 0);
			int werr = write_result(line);
			if (link_fd >= 0) {
				// stdout is the 3dslink host
				fputs(line, stdout);
				printf("result file: %s\n", werr == 0 ? "written" : "FAILED");
				fflush(stdout);
			} else {
				printf("\x1b[8;2H%s", line);
				printf("\x1b[9;2Hresult file: %s\n", werr == 0 ? "written" : "FAILED");
			}
			reported = true;
		} else if (reported && autoexit && ++frame >= RESULT_FRAME + AUTOEXIT_DELAY) {
			break;
		}

		gfxFlushBuffers();
		gfxSwapBuffers();
		gspWaitForVBlank();
	}

	if (link_fd >= 0) close(link_fd);
	if (soc_buffer != NULL) {
		socExit();
		free(soc_buffer);
	}
	gfxExit();
	return 0;
}
