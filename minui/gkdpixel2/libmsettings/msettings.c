#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

#include "msettings.h"

///////////////////////////////////////

#define SETTINGS_VERSION 2
typedef struct Settings {
	int version; // future proofing
	int brightness;
	int headphones;
	int speaker;
	int unused[2]; // for future use
	// NOTE: doesn't really need to be persisted but still needs to be shared
	int jack;
	int hdmi;
} Settings;
static Settings DefaultSettings = {
	.version = SETTINGS_VERSION,
	.brightness = 7,
	.headphones = 4,
	.speaker = 8,
	.jack = 0,
	.hdmi = 0,
};
static Settings* settings;
static Settings private_settings; // FASTBOOT: used only if shared memory is unavailable

#define SHM_KEY "/SharedSettings"
static char SettingsPath[256];
static int shm_fd = -1;
static int is_host = 0;
static int is_shared = 0;
static int shm_size = sizeof(Settings);

#define BACKLIGHT_PATH "/sys/class/backlight/backlight/bl_power"
#define BRIGHTNESS_PATH "/sys/class/backlight/backlight/brightness"
#define JACK_STATE_PATH "/sys/bus/platform/devices/singleadc-joypad/hp"
#define HDMI_STATE_PATH "/sys/class/extcon/hdmi/cable.0/state"

#define BRIGHTNESS_MIN 0
#define BRIGHTNESS_MAX 10
#define VOLUME_MIN 0
#define VOLUME_MAX 20
#define RAW_BRIGHTNESS_MAX 255
#define RAW_VOLUME_MAX 100

static int clamp(int value, int min, int max) {
	return value<min ? min : value>max ? max : value;
}

static int getInt(char* path) {
	int i = 0;
	FILE *file = fopen(path, "r");
	if (file!=NULL) {
		if (fscanf(file, "%i", &i)!=1) i = 0;
		fclose(file);
	}
	return i;
}

// FASTBOOT: launch-fast.sh exports MINUI_FASTBOOT=1. Rescue mode (stock systemd
// + Sway + PipeWire) runs these same binaries without it, so the audio calls
// below fall back to what the base wayland port did there.
static int isFastboot(void) {
	static int fastboot = -1;
	if (fastboot<0) {
		const char* value = getenv("MINUI_FASTBOOT");
		fastboot = value && value[0]=='1';
	}
	return fastboot;
}

static void run(const char* cmd) {
	int status = system(cmd);
	if (status!=0) fprintf(stderr, "msettings: `%s` failed (status %i)\n", cmd, status);
}

// defaults, overlaid with the saved file when it's intact; values always clamped
static void loadSettings(Settings* out) {
	*out = DefaultSettings;
	int fd = open(SettingsPath, O_RDONLY);
	if (fd>=0) {
		Settings saved;
		if (read(fd, &saved, sizeof(saved))==(ssize_t)sizeof(saved) && saved.version==SETTINGS_VERSION) *out = saved;
		close(fd);
	}
	out->brightness = clamp(out->brightness, BRIGHTNESS_MIN, BRIGHTNESS_MAX);
	out->headphones = clamp(out->headphones, VOLUME_MIN, VOLUME_MAX);
	out->speaker = clamp(out->speaker, VOLUME_MIN, VOLUME_MAX);
}

void InitSettings(void) {
	const char* userdata = getenv("USERDATA_PATH");
	snprintf(SettingsPath, sizeof(SettingsPath), "%s/msettings.bin", userdata ? userdata : "/tmp");

	shm_fd = shm_open(SHM_KEY, O_RDWR | O_CREAT | O_EXCL, 0644); // see if it exists
	if (shm_fd==-1 && errno==EEXIST) { // already exists
		puts("Settings client");
		shm_fd = shm_open(SHM_KEY, O_RDWR, 0644);
		// the host sizes and fills the object right after creating it; mapping it
		// before it's sized means SIGBUS on first access, so wait (briefly) for that
		struct stat st;
		int sized = 0;
		for (int i=0; shm_fd>=0 && i<100; i++) {
			if (fstat(shm_fd, &st)==0 && st.st_size>=shm_size) { sized = 1; break; }
			usleep(1000);
		}
		if (sized) {
			settings = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
			for (int i=0; settings!=MAP_FAILED && settings->version==0 && i<100; i++) usleep(1000);
		}
	}
	else if (shm_fd>=0) { // host
		puts("Settings host"); // should always be keymon
		is_host = 1;
		// load first so clients never see a half-populated struct
		Settings loaded;
		loadSettings(&loaded);
		if (ftruncate(shm_fd, shm_size)==0) {
			settings = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
			if (settings!=MAP_FAILED) *settings = loaded;
		}

		// these shouldn't be persisted
		// settings->jack = 0;
		// settings->hdmi = 0;
	}

	if (settings==NULL || settings==MAP_FAILED) {
		// FASTBOOT: no usable shared memory (e.g. /dev/shm didn't mount). Keep
		// working with a private copy instead of crashing; changes made by other
		// processes just won't show up live.
		fprintf(stderr, "msettings: shared settings unavailable (%s); using a private copy\n", strerror(errno));
		if (is_host) shm_unlink(SHM_KEY); // don't leave a zero-length object for clients
		is_host = 0;
		settings = &private_settings;
		loadSettings(settings);
	}
	else {
		is_shared = 1;
	}

	int jack = getInt(JACK_STATE_PATH);
	int hdmi = getInt(HDMI_STATE_PATH);
	printf("brightness: %i (hdmi: %i)\nspeaker: %i (jack: %i)\n", settings->brightness, hdmi, settings->speaker, jack); fflush(stdout);

	// FASTBOOT: apply jack, hdmi and volume once. (SetJack() then SetHDMI() set
	// the volume twice, and each pass spawned amixer and synced the disk.)
	settings->hdmi = hdmi;
	SetJack(jack); // switches outputs and applies the volume (skipped under hdmi)
	if (hdmi) SetRawVolume(RAW_VOLUME_MAX);

	SetBrightness(GetBrightness());
	// system("echo $(< " BRIGHTNESS_PATH ")");
}
void QuitSettings(void) {
	if (is_shared) munmap(settings, shm_size);
	if (shm_fd>=0) close(shm_fd);
	if (is_host) shm_unlink(SHM_KEY);
}
static void SaveSettings(void) {
	int fd = open(SettingsPath, O_CREAT|O_WRONLY, 0644);
	if (fd>=0) {
		if (write(fd, settings, shm_size)!=shm_size) fprintf(stderr, "msettings: short write to %s\n", SettingsPath);
		fsync(fd); // FASTBOOT: flush this file only, not a global sync() per volume step
		close(fd);
	}
}

int GetBrightness(void) { // 0-10
	return settings->brightness;
}
void SetBrightness(int value) {
	if (settings->hdmi) return;

	value = clamp(value, BRIGHTNESS_MIN, BRIGHTNESS_MAX);
	// TODO: redo, range is 0-255
	static const int raw[BRIGHTNESS_MAX+1] = { 4, 6, 10, 16, 32, 48, 64, 96, 128, 192, 255 };
	SetRawBrightness(raw[value]);
	if (settings->brightness!=value) {
		settings->brightness = value;
		SaveSettings();
	}
}

int GetVolume(void) { // 0-20
	return settings->jack ? settings->headphones : settings->speaker;
}
void SetVolume(int value) {
	if (settings->hdmi) return;

	// FASTBOOT: clamp like SetBrightness; an out-of-range value used to reach ALSA
	// as e.g. 5000% and could take hundreds of presses to walk back
	value = clamp(value, VOLUME_MIN, VOLUME_MAX);
	int* current = settings->jack ? &settings->headphones : &settings->speaker;
	int changed = *current!=value;
	*current = value;

	SetRawVolume(value * RAW_VOLUME_MAX / VOLUME_MAX);
	if (changed) SaveSettings();
}

void SetRawBrightness(int val) { // 0 - 255
	if (settings->hdmi) return;

	val = clamp(val, 0, RAW_BRIGHTNESS_MAX);
	// printf("SetRawBrightness(%i)\n", val); fflush(stdout);
	int fd = open(BRIGHTNESS_PATH, O_WRONLY);
	if (fd>=0) {
		dprintf(fd,"%d",val);
		close(fd);
	}
}
void SetRawVolume(int val) { // 0 - 100
	val = clamp(val, 0, RAW_VOLUME_MAX);
	// printf("SetRawVolume(%i)\n", val); fflush(stdout);
	char cmd[128];
	if (isFastboot()) {
		// FASTBOOT: audio flows through the 'minui' softvol pcm (asound.conf),
		// since the codec exposes no volume control. The softvol's raw range is
		// exactly 0-100, so val maps 1:1.
		snprintf(cmd, sizeof(cmd), "amixer -q -c 0 cset name='MinUI Volume' %i,%i >/dev/null 2>&1", val, val);
	}
	else {
		// rescue mode: PipeWire's 'Master' on the default ctl, as in the base port
		snprintf(cmd, sizeof(cmd), "amixer -q sset -M 'Master' %i%% >/dev/null 2>&1", val);
	}
	run(cmd);
}

// monitored and set by thread in keymon
int GetJack(void) {
	return settings->jack;
}
void SetJack(int value) {
	// printf("SetJack(%i)\n", value); fflush(stdout);

	settings->jack = value ? 1 : 0;
	if (isFastboot()) {
		// FASTBOOT: this kernel exposes plain Speaker/Headphone switches, not a
		// path mux. Set both in one amixer process (stdin batch mode).
		char cmd[160];
		snprintf(cmd, sizeof(cmd), "printf 'sset Speaker %s\\nsset Headphone on\\n' | amixer -q -c 0 -s >/dev/null 2>&1", value ? "off" : "on");
		run(cmd);
	}
	// rescue mode: leave output routing to the stock stack (the base port's
	// 'Playback Path' command matched no control on this kernel)

	SetVolume(GetVolume());
}

int GetHDMI(void) {
	// printf("GetHDMI() %i\n", settings->hdmi); fflush(stdout);
	return settings->hdmi;
}
void SetHDMI(int value) {
	// printf("SetHDMI(%i)\n", value); fflush(stdout);

	// if (settings->hdmi!=value) system("/usr/lib/autostart/common/055-hdmi-check");

	settings->hdmi = value;
	if (value) SetRawVolume(RAW_VOLUME_MAX); // max
	else SetVolume(GetVolume()); // restore
}

int GetMute(void) { return 0; }
void SetMute(int value) { (void)value; }
