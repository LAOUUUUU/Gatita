# Install Gatita on an iPad (or iPhone) with Sideloadly

## What you need

- An iPad or iPhone running **iPadOS or iOS 27 or later**. The app won't install on older versions.
- A Mac or Windows computer with **Sideloadly** installed. Get it from the official site, sideloadly.io.
- A USB cable that carries data (not a charge-only cable).
- An Apple ID. A free one works. Use a spare one if you don't want to use your main Apple ID.
- `Gatita-{version}-alpha-ios.ipa`, from the {version} alpha release.

## Steps

1. **Plug the iPad into the computer.** Unlock the iPad and tap **Trust** when it asks whether to trust this computer.

2. **Turn on Developer Mode on the iPad.** Go to Settings → Privacy & Security → Developer Mode, switch it on, and restart when asked. After the restart, confirm Developer Mode.

3. **Open Sideloadly** and wait for your iPad to appear in the device list.

4. **Drag `Gatita-{version}-alpha-ios.ipa` into Sideloadly.** Enter your Apple ID and password, then click **Start**. If you have two-factor authentication, enter the code it sends you.

5. **Trust the app on the iPad.** The first launch is blocked until you trust it. Go to Settings → General → VPN & Device Management, tap your Apple ID under Developer App, then tap **Trust**.

6. **Open Gatita** from the home screen. It starts on a new chat. Paste your Gatita API key in Settings first.

## Renewing it

A free Apple ID install expires after **7 days**. When Gatita stops opening, repeat steps 1 to 5. Your chats stay on the device.

A free Apple ID can have only a few sideloaded apps at once, so remove any you no longer need.

## Troubleshooting

- **The iPad doesn't appear in Sideloadly:** try another cable or port, unlock the iPad, and check that it's trusted.
- **"Guru Meditation" or an install error:** update Sideloadly, then try again. Check that the iPad is on iPadOS 27 or later.
- **Gatita won't open after installing:** check the trust step (step 5) and that Developer Mode is on.

## Notes

- Sideloadly and the Settings menu names can change between versions. If a step doesn't match what you see, check sideloadly.io for current instructions.
- The app on iPad and iPhone is a question-only app. Project files, commands, and GitHub only work on the Mac.
