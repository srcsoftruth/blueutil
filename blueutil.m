// blueutil
//
// CLI for bluetooth on OSX: power, discoverable state, list, inquire devices, connect, info, …
// Uses private API from IOBluetooth framework (i.e. IOBluetoothPreference*()).
// https://github.com/toy/blueutil
//
// Originally written by Frederik Seiffert <ego@frederikseiffert.de> http://www.frederikseiffert.de/blueutil/
//
// Copyright (c) 2011-2019 Ivan Kuchin. See <LICENSE.txt> for details.

#define VERSION "2.5.1"

#import <IOBluetooth/IOBluetooth.h>

#include <getopt.h>
#include <regex.h>

#define eprintf(...) fprintf(stderr, ##__VA_ARGS__)

// private methods
int IOBluetoothPreferencesAvailable();

int IOBluetoothPreferenceGetControllerPowerState();
void IOBluetoothPreferenceSetControllerPowerState(int state);

int IOBluetoothPreferenceGetDiscoverableState();
void IOBluetoothPreferenceSetDiscoverableState(int state);

// short names
typedef int (*getterFunc)();
typedef bool (*setterFunc)(int);

bool BTSetParamState(int state, getterFunc getter, void (*setter)(int), char *name) {
	if (state == getter()) return true;

	setter(state);

	for (int i = 0; i <= 100; i++) {
		if (i) usleep(100000);
		if (state == getter()) return true;
	}

	eprintf("Failed to switch bluetooth %s %s in 10 seconds\n", name, state ? "on" : "off");
	return false;
}

#define BTAvaliable IOBluetoothPreferencesAvailable

#define BTPowerState IOBluetoothPreferenceGetControllerPowerState
bool BTSetPowerState(int state) {
	return BTSetParamState(state, BTPowerState, IOBluetoothPreferenceSetControllerPowerState, "power");
}

#define BTDiscoverableState IOBluetoothPreferenceGetDiscoverableState
bool BTSetDiscoverableState(int state) {
	return BTSetParamState(state, BTDiscoverableState, IOBluetoothPreferenceSetDiscoverableState, "discoverable");
}

#define io_puts(io, string) fputs (string"\n", io)

void usage(FILE *io) {
	io_puts(io, "blueutil v"VERSION);
	io_puts(io, "");
	io_puts(io, "Usage:");
	io_puts(io, "  blueutil [options]");
	io_puts(io, "");
	io_puts(io, "Without options outputs current state");
	io_puts(io, "");
	io_puts(io, "    -p, --power               output power state as 1 or 0");
	io_puts(io, "    -p, --power STATE         set power state");
	io_puts(io, "    -d, --discoverable        output discoverable state as 1 or 0");
	io_puts(io, "    -d, --discoverable STATE  set discoverable state");
	io_puts(io, "");
	io_puts(io, "        --favourites          list favourite devices");
	io_puts(io, "        --inquiry [T]         inquiry devices in range, 10 seconds duration by default excluding time for name updates");
	io_puts(io, "        --paired              list paired devices");
	io_puts(io, "        --recent [N]          list recently used devices, 10 by default");
	io_puts(io, "");
	io_puts(io, "        --info ID             show information about device");
	io_puts(io, "        --is-connected ID     connected state of device as 1 or 0");
	io_puts(io, "        --connect ID          create a connection to device");
	io_puts(io, "        --disconnect ID       close the connection to device");
	io_puts(io, "        --pair ID [PIN]       pair with device, optional PIN of up to 16 characters will be used instead of interactive input if requested in specific pair mode");
	io_puts(io, "");
	io_puts(io, "        --format FORMAT       change output format of info and all listing commands");
	io_puts(io, "");
	io_puts(io, "    -h, --help                this help");
	io_puts(io, "    -v, --version             show version");
	io_puts(io, "");
	io_puts(io, "STATE can be one of: 1, on, 0, off, toggle");
	io_puts(io, "ID can be either address in form xxxxxxxxxxxx, xx-xx-xx-xx-xx-xx or xx:xx:xx:xx:xx:xx, or name of device to search in used devices");
	io_puts(io, "FORMAT can be one of:");
	io_puts(io, "  default - human readable text output not intended for consumption by scripts");
	io_puts(io, "  new-default - human readable comma separated key-value pairs (EXPERIMENTAL, THE BEHAVIOUR MAY CHANGE)");
	io_puts(io, "  json - compact JSON");
	io_puts(io, "  json-pretty - pretty printed JSON");
}

char *next_optarg(int argc, char *argv[]) {
	if (
		optind < argc &&
		NULL != argv[optind] &&
		'-' != argv[optind][0]
	) {
		return argv[optind++];
	} else {
		return NULL;
	}
}

// getopt_long doesn't consume optional argument separated by space
// https://stackoverflow.com/a/32575314
void extend_optarg(int argc, char *argv[]) {
	if (!optarg) optarg = next_optarg(argc, argv);
}

bool parse_state_arg(char *arg, int *state) {
	if (
		0 == strcasecmp(arg, "1") ||
		0 == strcasecmp(arg, "on")
	) {
		if (state) *state = 1;
		return true;
	}

	if (
		0 == strcasecmp(arg, "0") ||
		0 == strcasecmp(arg, "off")
	) {
		if (state) *state = 0;
		return true;
	}

	if (
		0 == strcasecmp(arg, "toggle")
	) {
		if (state) *state = -1;
		return true;
	}

	return false;
}

bool check_device_address_arg(char *arg) {
	regex_t regex;

	if (0 != regcomp(&regex, "^[0-9a-f]{2}([0-9a-f]{10}|(-[0-9a-f]{2}){5}|(:[0-9a-f]{2}){5})$", REG_EXTENDED | REG_ICASE | REG_NOSUB)) {
		eprintf("Failed compiling regex");
		exit(EXIT_FAILURE);
	}

	int result = regexec(&regex, arg, 0, NULL, 0);

	regfree(&regex);

	switch (result) {
		case 0:
			return true;
		case REG_NOMATCH:
			return false;
		default:
			eprintf("Failed matching regex");
			exit(EXIT_FAILURE);
	}
}

bool parse_unsigned_long_arg(char *arg, unsigned long *number) {
	regex_t regex;

	if (0 != regcomp(&regex, "^[[:digit:]]+$", REG_EXTENDED | REG_NOSUB)) {
		eprintf("Failed compiling regex");
		exit(EXIT_FAILURE);
	}

	int result = regexec(&regex, arg, 0, NULL, 0);

	regfree(&regex);

	switch (result) {
		case 0:
			if (number) *number = strtoul(arg, NULL, 10);
			return true;
		case REG_NOMATCH:
			return false;
		default:
			eprintf("Failed matching regex");
			exit(EXIT_FAILURE);
	}
}

IOBluetoothDevice *get_device(char *id) {
	NSString *nsId = [NSString stringWithCString:id encoding:[NSString defaultCStringEncoding]];

	IOBluetoothDevice *device = nil;

	if (check_device_address_arg(id)) {
		device = [IOBluetoothDevice deviceWithAddressString:nsId];

		if (!device) {
			eprintf("Device not found by address: %s\n", id);
			exit(EXIT_FAILURE);
		}
	} else {
		NSArray *recentDevices = [IOBluetoothDevice recentDevices:0];

		if (!recentDevices) {
			eprintf("No recent devices to search for: %s\n", id);
			exit(EXIT_FAILURE);
		}

		NSArray *byName = [recentDevices filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", nsId]];
		if (byName.count > 0) {
			device = byName.firstObject;
		}

		if (!device) {
			eprintf("Device not found by name: %s\n", id);
			exit(EXIT_FAILURE);
		}
	}

	return device;
}

void list_devices_default(NSArray *devices, bool first_only) {
	for (IOBluetoothDevice* device in devices) {
		printf("address: %s", [[device addressString] UTF8String]);
		if ([device isConnected]) {
			printf(", connected (%s, %d dBm)", [device isIncoming] ? "slave" : "master", [device rawRSSI]);
		} else {
			printf(", not connected");
		}
		printf(", %s", [device isFavorite] ? "favourite" : "not favourite");
		printf(", %s", [device isPaired] ? "paired" : "not paired");
		printf(", name: \"%s\"", [device name] ? [[device name] UTF8String] : "-");
		printf(", recent access date: %s", [device recentAccessDate] ? [[[device recentAccessDate] description] UTF8String] : "-");
		printf("\n");
		if (first_only) break;
	}
}

void list_devices_new_default(NSArray *devices, bool first_only) {
	const char *separator = first_only ? "\n" : ", ";
	for (IOBluetoothDevice* device in devices) {
		printf("address: %s%s", [[device addressString] UTF8String], separator);
		printf("recent access: %s%s", [device recentAccessDate] ? [[[device recentAccessDate] description] UTF8String] : "-", separator);
		printf("favourite: %s%s", [device isFavorite] ? "yes" : "no", separator);
		printf("paired: %s%s", [device isPaired] ? "yes" : "no", separator);
		printf("connected: %s%s", [device isConnected] ? ([device isIncoming] ? "slave" : "master") : "no", separator);
		printf("rssi: %s%s", [device isConnected] ? [[NSString stringWithFormat: @"%d", [device RSSI]] UTF8String] : "-", separator);
		printf("raw rssi: %s%s", [device isConnected] ? [[NSString stringWithFormat: @"%d", [device rawRSSI]] UTF8String] : "-", separator);
		printf("name: %s\n", [device name] ? [[device name] UTF8String] : "-");
		if (first_only) break;
	}
}

void list_devices_json(NSArray *devices, bool first_only, bool pretty) {
	NSMutableArray *descriptions = [NSMutableArray arrayWithCapacity:[devices count]];

	// https://stackoverflow.com/a/16254918/96823
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[dateFormatter setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];
	[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];

	for (IOBluetoothDevice* device in devices) {
		NSMutableDictionary *description = [NSMutableDictionary dictionaryWithDictionary:@{
			@"address": [device addressString],
			@"name": [device name] ? [device name] : [NSNull null],
			@"recentAccessDate": [device recentAccessDate] ? [dateFormatter stringFromDate:[device recentAccessDate]] : [NSNull null],
			@"favourite": [device isFavorite] ? @(YES) : @(NO),
			@"paired": [device isPaired] ? @(YES) : @(NO),
			@"connected": [device isConnected] ? @(YES) : @(NO),
		}];

		if ([device isConnected]) {
			description[@"slave"] = [device isIncoming] ? @(YES) : @(NO);
			description[@"RSSI"] = [NSNumber numberWithChar:[device RSSI]];
			description[@"rawRSSI"] = [NSNumber numberWithChar:[device rawRSSI]];
		}

		[descriptions addObject:description];
	}

	NSOutputStream *stdout = [NSOutputStream outputStreamToFileAtPath:@"/dev/stdout" append:NO];
	[stdout open];
	[NSJSONSerialization writeJSONObject:(first_only ? [descriptions firstObject] : descriptions) toStream:stdout options:(pretty ? NSJSONWritingPrettyPrinted : 0) error:NULL];
	if (pretty) {
		[stdout write:(const uint8_t *)"\n" maxLength:1];
	}
	[stdout close];
}

void list_devices_json_default(NSArray *devices, bool first_only) {
	list_devices_json(devices, first_only, false);
}

void list_devices_json_pretty(NSArray *devices, bool first_only) {
	list_devices_json(devices, first_only, true);
}

typedef void (*formatterFunc)(NSArray *, bool);

bool parse_output_formatter(char *arg, formatterFunc *formatter) {
	if (0 == strcasecmp(arg, "default")) {
		if (formatter) *formatter = list_devices_default;
		return true;
	}

	if (0 == strcasecmp(arg, "new-default")) {
		if (formatter) *formatter = list_devices_new_default;
		return true;
	}

	if (0 == strcasecmp(arg, "json")) {
		if (formatter) *formatter = list_devices_json_default;
		return true;
	}

	if (0 == strcasecmp(arg, "json-pretty")) {
		if (formatter) *formatter = list_devices_json_pretty;
		return true;
	}

	return false;
}

@interface DeviceInquiryRunLoopStopper : NSObject <IOBluetoothDeviceInquiryDelegate>
@end
@implementation DeviceInquiryRunLoopStopper
- (void)deviceInquiryComplete:(__unused IOBluetoothDeviceInquiry *)sender error:(__unused IOReturn)error aborted:(__unused BOOL)aborted {
	CFRunLoopStop(CFRunLoopGetCurrent());
}
@end

static inline bool is_caseabbr(const char* name, const char* str) {
	size_t length = strlen(str);
	if (length < 1) length = 1;
	return strncasecmp(name, str, length) == 0;
}

const char* hciErrorDescriptions[] = {
	[0x01] = "Unknown HCI Command",
	[0x02] = "No Connection",
	[0x03] = "Hardware Failure",
	[0x04] = "Page Timeout",
	[0x05] = "Authentication Failure",
	[0x06] = "Key Missing",
	[0x07] = "Memory Full",
	[0x08] = "Connection Timeout",
	[0x09] = "Max Number of Connections",
	[0x0a] = "Max Number of SCO Connections to a Device",
	[0x0b] = "ACL Connection Already Exists",
	[0x0c] = "Command Disallowed",
	[0x0d] = "Host Rejected Limited Resources",
	[0x0e] = "Host Rejected Security Reasons",
	[0x0f] = "Host Rejected Remote Device Is Personal / Host Rejected Unacceptable Device Address (2.0+)",
	[0x10] = "Host Timeout",
	[0x11] = "Unsupported Feature or Parameter Value",
	[0x12] = "Invalid HCI Command Parameters",
	[0x13] = "Other End Terminated Connection User Ended",
	[0x14] = "Other End Terminated Connection Low Resources",
	[0x15] = "Other End Terminated Connection About to Power Off",
	[0x16] = "Connection Terminated by Local Host",
	[0x17] = "Repeated Attempts",
	[0x18] = "Pairing Not Allowed",
	[0x19] = "Unknown LMP PDU",
	[0x1a] = "Unsupported Remote Feature",
	[0x1b] = "SCO Offset Rejected",
	[0x1c] = "SCO Interval Rejected",
	[0x1d] = "SCO Air Mode Rejected",
	[0x1e] = "Invalid LMP Parameters",
	[0x1f] = "Unspecified Error",
	[0x20] = "Unsupported LMP Parameter Value",
	[0x21] = "Role Change Not Allowed",
	[0x22] = "LMP Response Timeout",
	[0x23] = "LMP Error Transaction Collision",
	[0x24] = "LMP PDU Not Allowed",
	[0x25] = "Encryption Mode Not Acceptable",
	[0x26] = "Unit Key Used",
	[0x27] = "QoS Not Supported",
	[0x28] = "Instant Passed",
	[0x29] = "Pairing With Unit Key Not Supported",
	[0x2a] = "Different Transaction Collision",
	[0x2c] = "QoS Unacceptable Parameter",
	[0x2d] = "QoS Rejected",
	[0x2e] = "Channel Classification Not Supported",
	[0x2f] = "Insufficient Security",
	[0x30] = "Parameter Out of Mandatory Range",
	[0x31] = "Role Switch Pending",
	[0x34] = "Reserved Slot Violation",
	[0x35] = "Role Switch Failed",
	[0x36] = "Extended Inquiry Response Too Large",
	[0x37] = "Secure Simple Pairing Not Supported by Host",
	[0x38] = "Host Busy Pairing",
	[0x39] = "Connection Rejected Due to No Suitable Channel Found",
	[0x3a] = "Controller Busy",
	[0x3b] = "Unacceptable Connection Interval",
	[0x3c] = "Directed Advertising Timeout",
	[0x3d] = "Connection Terminated Due to MIC Failure",
	[0x3e] = "Connection Failed to Be Established",
	[0x3f] = "MAC Connection Failed",
	[0x40] = "Coarse Clock Adjustment Rejected",
};

@interface DevicePairDelegate : NSObject <IOBluetoothDevicePairDelegate>
@property (readonly) IOReturn errorCode;
@property char* requestedPin;
@end
@implementation DevicePairDelegate
- (const char*)errorDescription {
	if (
		_errorCode >= 0 &&
		(unsigned)_errorCode < sizeof(hciErrorDescriptions) / sizeof(hciErrorDescriptions[0]) &&
		hciErrorDescriptions[_errorCode]
	) {
		return hciErrorDescriptions[_errorCode];
	} else {
		return "UNKNOWN ERROR";
	}
}

- (void)devicePairingFinished:(__unused id)sender error:(IOReturn)error {
	_errorCode = error;
	CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)devicePairingPINCodeRequest:(id)sender {
	BluetoothPINCode pinCode;
	ByteCount pinCodeSize;

	if (_requestedPin) {
		eprintf(
			"Input pin %.16s on \"%s\" (%s)\n",
			_requestedPin,
			[[[sender device] name] UTF8String],
			[[[sender device] addressString] UTF8String]
		);

		pinCodeSize = strlen(_requestedPin);
		if (pinCodeSize > 16) pinCodeSize = 16;
		strncpy((char *)pinCode.data, _requestedPin, pinCodeSize);
	} else {
		eprintf(
			"Type pin code (up to 16 characters) for \"%s\" (%s) and press Enter: ",
			[[[sender device] name] UTF8String],
			[[[sender device] addressString] UTF8String]
		);

		uint input_size = 16 + 2;
		char input[input_size];
		fgets(input, input_size, stdin);
		input[strcspn(input, "\n")] = 0;

		pinCodeSize = strlen(input);
		strncpy((char *)pinCode.data, input, pinCodeSize);
	}

	[sender replyPINCode:pinCodeSize PINCode:&pinCode];
}

- (void)devicePairingUserConfirmationRequest:(id)sender numericValue:(BluetoothNumericValue)numericValue {
	eprintf(
		"Does \"%s\" (%s) display number %06u (yes/no)? ",
		[[[sender device] name] UTF8String],
		[[[sender device] addressString] UTF8String],
		numericValue
	);

	uint input_size = 3 + 2;
	char input[input_size];
	fgets(input, input_size, stdin);
	input[strcspn(input, "\n")] = 0;

	if (is_caseabbr("yes", input)) {
		[sender replyUserConfirmation:YES];
		return;
	}

	if (is_caseabbr("no", input)) {
		[sender replyUserConfirmation:NO];
		return;
	}
}

- (void)devicePairingUserPasskeyNotification:(id)sender passkey:(BluetoothPasskey)passkey {
	eprintf(
		"Input passkey %06u on \"%s\" (%s)\n",
		passkey,
		[[[sender device] name] UTF8String],
		[[[sender device] addressString] UTF8String]
	);
}
@end

int main(int argc, char *argv[]) {
	if (!BTAvaliable()) {
		io_puts(stderr, "Error: Bluetooth not available!");
		return EXIT_FAILURE;
	}

	if (argc == 1) {
		printf("Power: %d\nDiscoverable: %d\n", BTPowerState(), BTDiscoverableState());
		return EXIT_SUCCESS;
	}

	enum {
		arg_power = 'p',
		arg_discoverable = 'd',
		arg_help = 'h',
		arg_version = 'v',

		arg_favourites = 256,
		arg_inquiry,
		arg_paired,
		arg_recent,

		arg_info,
		arg_is_connected,
		arg_connect,
		arg_disconnect,
		arg_pair,

		arg_format,
	};

	const char* optstring = "p::d::hv";
	static struct option long_options[] = {
		{"power",           optional_argument, NULL, arg_power},
		{"discoverable",    optional_argument, NULL, arg_discoverable},

		{"favourites",      no_argument,       NULL, arg_favourites},
		{"inquiry",         optional_argument, NULL, arg_inquiry},
		{"paired",          no_argument,       NULL, arg_paired},
		{"recent",          optional_argument, NULL, arg_recent},

		{"info",            required_argument, NULL, arg_info},
		{"is-connected",    required_argument, NULL, arg_is_connected},
		{"connect",         required_argument, NULL, arg_connect},
		{"disconnect",      required_argument, NULL, arg_disconnect},
		{"pair",            required_argument, NULL, arg_pair},

		{"format",          required_argument, NULL, arg_format},

		{"help",            no_argument,       NULL, arg_help},
		{"version",         no_argument,       NULL, arg_version},

		{NULL, 0, NULL, 0}
	};

	formatterFunc list_devices = list_devices_default;

	int ch;
	while ((ch = getopt_long(argc, argv, optstring, long_options, NULL)) != -1) {
		switch (ch) {
			case arg_power:
			case arg_discoverable:
				extend_optarg(argc, argv);

				if (optarg && !parse_state_arg(optarg, NULL)) {
					eprintf("Unexpected value: %s\n", optarg);
					return EXIT_FAILURE;
				}

				break;
			case arg_favourites:
			case arg_paired:
				break;
			case arg_inquiry:
			case arg_recent:
				extend_optarg(argc, argv);

				if (optarg && !parse_unsigned_long_arg(optarg, NULL)) {
					eprintf("Expected number, got: %s\n", optarg);
					return EXIT_FAILURE;
				}

				break;
			case arg_info:
			case arg_is_connected:
			case arg_connect:
			case arg_disconnect:
				break;
			case arg_pair: {
				char *requested_pin = next_optarg(argc, argv);

				if (requested_pin && strlen(requested_pin) > 16) {
					eprintf("Pairing pin can't be longer than 16 characters, got %lu (%s)\n", strlen(requested_pin), requested_pin);
					return EXIT_FAILURE;
				}

			} break;
			case arg_format:
				if (!parse_output_formatter(optarg, &list_devices)) {
					eprintf("Unexpected format: %s\n", optarg);
					return EXIT_FAILURE;
				}

				break;
			case arg_version:
				io_puts(stdout, VERSION);
				return EXIT_SUCCESS;
			case arg_help:
				usage(stdout);
				return EXIT_SUCCESS;
			default:
				usage(stderr);
				return EXIT_FAILURE;
		}
	}

	if (optind < argc) {
		eprintf("Unexpected arguments: %s", argv[optind++]);
		while (optind < argc) {
			eprintf(", %s", argv[optind++]);
		}
		eprintf("\n");
		return EXIT_FAILURE;
	}

	optind = 1;
	while ((ch = getopt_long(argc, argv, optstring, long_options, NULL)) != -1) {
		switch (ch) {
			case arg_power:
			case arg_discoverable:
				extend_optarg(argc, argv);
				if (optarg) {
					setterFunc setter = ch == 'p' ? BTSetPowerState : BTSetDiscoverableState;

					int state;
					parse_state_arg(optarg, &state);
					if (state == -1) {
						getterFunc getter = ch == 'p' ? BTPowerState : BTDiscoverableState;

						state = !getter();
					}

					if (!setter(state)) {
						return EXIT_FAILURE;
					}
				} else {
					getterFunc getter = ch == 'p' ? BTPowerState : BTDiscoverableState;

					printf("%d\n", getter());
				}

				break;
			case arg_favourites:
				list_devices([IOBluetoothDevice favoriteDevices], false);

				break;
			case arg_paired:
				list_devices([IOBluetoothDevice pairedDevices], false);

				break;
			case arg_inquiry: {
				IOBluetoothDeviceInquiry *inquirer = [IOBluetoothDeviceInquiry inquiryWithDelegate:[[DeviceInquiryRunLoopStopper alloc] init]];

				extend_optarg(argc, argv);
				if (optarg) {
					unsigned long t;
					parse_unsigned_long_arg(optarg, &t);
					[inquirer setInquiryLength:t];
				}

				[inquirer start];
				CFRunLoopRun();
				[inquirer stop];

				list_devices([inquirer foundDevices], false);

			} break;
			case arg_recent: {
				unsigned long n = 10;

				extend_optarg(argc, argv);
				if (optarg) parse_unsigned_long_arg(optarg, &n);

				list_devices([IOBluetoothDevice recentDevices:n], false);

			} break;
			case arg_info:
				list_devices(@[get_device(optarg)], true);

				break;
			case arg_is_connected:
				printf("%d\n", [get_device(optarg) isConnected] ? 1 : 0);

				break;
			case arg_connect:
				if ([get_device(optarg) openConnection] != kIOReturnSuccess) {
					eprintf("Failed to connect \"%s\"\n", optarg);
					return EXIT_FAILURE;
				}

				break;
			case arg_disconnect:
				if ([get_device(optarg) closeConnection] != kIOReturnSuccess) {
					eprintf("Failed to disconnect \"%s\"\n", optarg);
					return EXIT_FAILURE;
				}

				break;
			case arg_pair: {
				IOBluetoothDevice* device = get_device(optarg);
				DevicePairDelegate* delegate = [[DevicePairDelegate alloc] init];
				IOBluetoothDevicePair *pairer = [IOBluetoothDevicePair pairWithDevice:device];
				pairer.delegate = delegate;

				delegate.requestedPin = next_optarg(argc, argv);

				if ([pairer start] != kIOReturnSuccess) {
					eprintf("Failed to start pairing with \"%s\"\n", optarg);
					return EXIT_FAILURE;
				}
				CFRunLoopRun();
				[pairer stop];

				if (![device isPaired]) {
					eprintf("Failed to pair \"%s\" with error 0x%02x (%s)\n", optarg, [delegate errorCode], [delegate errorDescription]);
					return EXIT_FAILURE;
				}

			} break;
		}
	}

	return EXIT_SUCCESS;
}
