# BuzzPair for macOS

<div align="center">
  <img src="https://github.com/chhabraadhruv/buzzpair/raw/main/assets/buzzpair-icon.png" alt="BuzzPair Logo" width="200" height="200">
</div>

A native macOS application that brings Google Fast Pair functionality to your Mac, providing a seamless connection experience for Fast Pair compatible earbuds and headphones.

## Features

- **Quick Connect**: Instantly detect and connect to Google Fast Pair compatible devices
- **AirPods-like Experience**: Get the same seamless pairing experience as AirPods, but for your Google Fast Pair devices
- **ANC Controls**: Toggle between Noise Cancellation, Transparency, and Off modes
- **Battery Monitoring**: View real-time battery levels for your connected devices
- **Volume & EQ Controls**: Adjust audio settings directly from the app
- **Menu Bar Integration**: Quick access to your device controls from the macOS menu bar
- **Smart Notifications**: Receive alerts when compatible devices are detected nearby

## Requirements

- macOS 12.0 (Monterey) or later
- Bluetooth 4.0+ capable Mac
- Google Fast Pair compatible audio devices

## Installation

### Method 1: Download Release

1. Go to the [Releases](https://github.com/yourusername/buzzpair/releases) page
2. Download the latest version of BuzzPair
3. Drag the app to your Applications folder
4. Launch BuzzPair

### Method 2: Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/buzzpair.git
   cd buzzpair
   ```

2. Open the project in Xcode:
   ```bash
   open BuzzPair.xcodeproj
   ```

3. Build the project (⌘+B) and run (⌘+R)

4. To create a standalone app, select Product > Archive, then distribute the app

## Supported Devices

BuzzPair works with a wide range of Google Fast Pair compatible devices, including:

- Google Pixel Buds (all models)
- Sony WH-1000XM series
- Bose QuietComfort Earbuds
- JBL wireless earbuds and headphones
- And many more Fast Pair compatible devices

## Usage Guide

### First-time Setup

1. Launch BuzzPair
2. Grant Bluetooth and Notification permissions when prompted
3. Put your earbuds/headphones in pairing mode
4. BuzzPair will automatically detect nearby Fast Pair devices
5. Click on a device to connect

### Controls

- **Connect/Disconnect**: One-click connection management
- **ANC Mode**: Toggle between Noise Cancellation, Transparency, and Off
- **Volume**: Adjust volume levels directly in the app
- **EQ Settings**: Choose from preset audio profiles

### Menu Bar Access

BuzzPair lives in your menu bar for quick access:
1. Click the earbuds icon in the menu bar
2. Select "Open BuzzPair" to show the main interface
3. Quick controls are available directly from the menu

## Privacy

BuzzPair prioritizes your privacy:

- No user data is collected or transmitted
- Device information remains local to your Mac
- No analytics or tracking are implemented
- No internet connection is required for core functionality

## Troubleshooting

### Common Issues

- **Device Not Showing Up**
  - Ensure your device is in pairing mode
  - Make sure Bluetooth is enabled on your Mac
  - Restart the BuzzPair app

- **Connection Failed**
  - Remove the device from your Bluetooth settings and try again
  - Restart your audio device
  - Ensure your device is fully charged

- **No Sound**
  - Check system sound settings
  - Ensure BuzzPair is set as the output device in macOS Sound preferences
  - Try disconnecting and reconnecting the device

### Getting Help

If you encounter issues not covered here:
- Check the [GitHub Issues](https://github.com/yourusername/buzzpair/issues) page
- Create a new issue with details about your problem
- Contact support at support@buzzpair.app

## Development Status

BuzzPair is currently in beta. We're actively working to improve compatibility with more devices and add new features.

## Contributing

Contributions are welcome! If you'd like to help improve BuzzPair:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Please read our [Contributing Guidelines](CONTRIBUTING.md) for more details.

## License

BuzzPair is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Credits

BuzzPair is developed and maintained by [Your Name/Organization].

Special thanks to:
- The SwiftUI community
- All beta testers who provided valuable feedback
- Contributors to the Google Fast Pair protocol documentation

---

*BuzzPair is not affiliated with or endorsed by Google, Inc. Google Fast Pair is a trademark of Google LLC.*
