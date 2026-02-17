#include "CSafeMemory.h"
#include <signal.h>
#include <setjmp.h>
#include <string.h>

static sigjmp_buf s_jumpBuffer;
static volatile sig_atomic_t s_guardActive = 0;

static struct sigaction s_previousSIGSEGV;
static struct sigaction s_previousSIGBUS;

static void safe_memory_signal_handler(int sig) {
	if (s_guardActive) {
		s_guardActive = 0;
		siglongjmp(s_jumpBuffer, 1);
	}
	// Not our guarded access — restore and re-raise
	signal(sig, SIG_DFL);
	raise(sig);
}

bool safe_memory_read(const void *source, void *dest, size_t size) {
	// Install signal handlers
	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_handler = safe_memory_signal_handler;
	sigemptyset(&action.sa_mask);
	action.sa_flags = 0;

	sigaction(SIGSEGV, &action, &s_previousSIGSEGV);
	sigaction(SIGBUS, &action, &s_previousSIGBUS);

	bool success;

	// Set recovery point
	s_guardActive = 1;
	if (sigsetjmp(s_jumpBuffer, 1) == 0) {
		// Normal path — attempt the read
		memcpy(dest, source, size);
		s_guardActive = 0;
		success = true;
	} else {
		// Signal handler jumped back here — read faulted
		success = false;
	}

	// Restore original handlers
	sigaction(SIGSEGV, &s_previousSIGSEGV, NULL);
	sigaction(SIGBUS, &s_previousSIGBUS, NULL);

	return success;
}
