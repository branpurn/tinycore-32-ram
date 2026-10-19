/*
 * xbench: a small x11perf-style benchmark for the graphics QEMU tests
 * (tests/gfx-bench.py). Each test runs to XSync, so the time includes
 * whatever the server (and the framebuffer driver behind it) does to get
 * the pixels to the screen within the request.
 *   xbench [test ...]    tests: scroll fill text move (default: all)
 * Output, one line per test:  xbench NAME OPS MS OPS_PER_S
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static Display *d;
static Window w;
static GC gc;
static int W = 600, H = 416, LH = 13;

static double now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static void report(const char *name, int n, double t0)
{
	double ms = now_ms() - t0;

	printf("xbench %s %d %.0f %.1f\n", name, n, ms, ms > 0 ? n * 1e3 / ms : 0);
	fflush(stdout);
}

/* rxvt-like scrolling: copy the window up one line, clear and draw the new line */
static void t_scroll(void)
{
	static const char line[] = "drwxr-xr-x    2 root     root          1024 Oct 19 00:00 scrolling text";
	int i, n = 300;
	double t0 = now_ms();

	for (i = 0; i < n; i++) {
		XCopyArea(d, w, w, gc, 0, LH, W, H - LH, 0, 0);
		XSetForeground(d, gc, WhitePixel(d, 0));
		XFillRectangle(d, w, gc, 0, H - LH, W, LH);
		XSetForeground(d, gc, BlackPixel(d, 0));
		XDrawString(d, w, gc, 2, H - 3, line, sizeof(line) - 1);
		XSync(d, False);
	}
	report("scroll", n, t0);
}

static void t_fill(void)
{
	int i, n = 400;
	double t0 = now_ms();

	srand(1);
	for (i = 0; i < n; i++) {
		XSetForeground(d, gc, rand() & 0xff);
		XFillRectangle(d, w, gc, rand() % (W - 200), rand() % (H - 150), 200, 150);
		XSync(d, False);
	}
	report("fill200x150", n, t0);
}

static void t_text(void)
{
	static const char s[] = "The quick brown fox jumps over the lazy dog 0123456789 ABCDEFGHIJKLMNOPQRSTUV";
	int i, n = 1500;
	double t0 = now_ms();

	XSetForeground(d, gc, BlackPixel(d, 0));
	XSetBackground(d, gc, WhitePixel(d, 0));
	for (i = 0; i < n; i++) {
		XDrawImageString(d, w, gc, 2, LH * (1 + i % (H / LH - 1)), s, sizeof(s) - 1);
		if (i % 20 == 19)
			XSync(d, False);
	}
	XSync(d, False);
	report("text80", n, t0);
}

/* move an override-redirect 300x200 window: CopyWindow + exposures */
static void t_move(void)
{
	XSetWindowAttributes a;
	Window m;
	int i, n = 120;
	double t0;

	a.override_redirect = True;
	a.background_pixel = 0x30;
	m = XCreateWindow(d, DefaultRootWindow(d), 20, 40, 300, 200, 1, CopyFromParent,
			  InputOutput, CopyFromParent, CWOverrideRedirect | CWBackPixel, &a);
	XMapRaised(d, m);
	XSync(d, False);
	XSetForeground(d, gc, 0x0f);
	for (i = 0; i < 200; i += 10)
		XDrawLine(d, m, gc, 0, i, 299, 199 - i);
	XSync(d, False);
	t0 = now_ms();
	for (i = 0; i < n; i++) {
		XMoveWindow(d, m, 20 + (i % 40) * 6, 40 + (i % 40) * 4);
		XSync(d, False);
	}
	report("move300x200", n, t0);
	XDestroyWindow(d, m);
	XSync(d, False);
}

int main(int argc, char **argv)
{
	XSetWindowAttributes a;
	XEvent e;
	int i;

	d = XOpenDisplay(NULL);
	if (!d) {
		fprintf(stderr, "xbench: cannot open display\n");
		return 1;
	}
	a.override_redirect = True;
	a.background_pixel = WhitePixel(d, 0);
	w = XCreateWindow(d, DefaultRootWindow(d), 10, 10, W, H, 0, CopyFromParent,
			  InputOutput, CopyFromParent, CWOverrideRedirect | CWBackPixel, &a);
	XSelectInput(d, w, ExposureMask);
	XMapRaised(d, w);
	XWindowEvent(d, w, ExposureMask, &e);
	gc = XCreateGC(d, w, 0, NULL);
	XSetGraphicsExposures(d, gc, False);
	XSync(d, False);
	for (i = argc > 1 ? 1 : 0; i < (argc > 1 ? argc : 1); i++) {
		const char *t = argc > 1 ? argv[i] : "all";
		int all = !strcmp(t, "all");

		if (all || !strcmp(t, "scroll"))
			t_scroll();
		if (all || !strcmp(t, "fill"))
			t_fill();
		if (all || !strcmp(t, "text"))
			t_text();
		if (all || !strcmp(t, "move"))
			t_move();
	}
	XCloseDisplay(d);
	return 0;
}
