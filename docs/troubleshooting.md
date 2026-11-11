# Troubleshooting

## No lid reading

Keep the case near the Mac and open and close it. Confirm Bluetooth is enabled
and AirSkip is allowed under **Privacy & Security → Bluetooth**.

Open **Troubleshoot** in AirSkip:

1. Use **Retry setup** to restart discovery and automatic recovery.
2. Check **Choose your AirPods**. Select your pair explicitly if several are
   paired or your AirPods were renamed. Use **Refresh devices** after pairing.
3. If another case was detected, select the correct **Nearby case**, or use
   **Find case again**. Repeat **The lid matches** before enabling.
4. Expand **Bluetooth diagnostics**. It shows packet counts, decoding counts,
   and signal strength. No keys or raw packets are displayed. If case packets
   arrive but decoding stays at zero, the case may need a different decoder.
   Testing has only been done with AirPods Pro 3; other cases may need changes.

If the animation already follows your lid, no key setup is needed. macOS can
provide an already decoded payload.

## Key recovery

Try the controls under **If AirSkip can’t read the lid**, stopping once the
animation responds:

1. **Load saved** reads AirSkip's previously saved key.
2. **Load paired** reads the selected pair's `MobileBluetooth` Keychain entry.
   Approve macOS access if asked.
3. **Read key** requests the current broadcast key from connected earbuds.
   Take both earbuds out and connect them to this Mac first. This experimental
   request times out after ten seconds; macOS may already own the connection.

Automatic setup tries each source at most once per pair per launch. Denying a
Keychain prompt stops automatic recovery for that pair. **Retry setup** allows
another attempt.

For manual import, open Keychain Access, select **System**, and find the
`MobileBluetooth` item for your AirPods. Show its password and copy only
`MagicAccEncKey` into **Import key manually** in AirSkip. It accepts 32 hex digits
or the hyphen-separated Keychain format. Keep this value private. **Forget saved
key** removes only AirSkip's copy; it does not change Bluetooth pairing.

Manual key replacement requires another lid match. Automatic recovery preserves
a saved match for the same case.

## Arrow keys do nothing

Allow the installed AirSkip app in **Privacy & Security → Accessibility**.
Enable AirSkip, bring YouTube in Google Chrome to the front, click the player,
and close AirSkip's controls. A focused search box or other text field blocks
key presses. Other focused controls may handle the right arrow differently.

The status below the repeat delay explains what is blocking skipping. In
**Troubleshoot → Keyboard access**, check Chrome focus and the number of arrow
key pairs posted. This count confirms posting, not that YouTube handled the key.
AirSkip requests Chrome's webpage accessibility support automatically; the
first focus check can take a few seconds while Chrome prepares it.

After sleep or locking, enable AirSkip again. If the signal has stopped,
repeat case discovery rather than assuming the last lid state is current.

## Signing and updates

Quit AirSkip before running the install command again. Keep the installed app
at the same path after granting permissions.

With no Apple signing certificate, the build uses ad hoc signing for local use.
After a changed build, macOS may require removing and re-adding AirSkip's entry
in Accessibility Settings. AirSkip does not reset system permissions itself.

For a persistent identity, list your available certificates and choose the
same one for each build:

```sh
security find-identity -v -p codesigning
AIRSKIP_SIGN_IDENTITY="YOUR_CERTIFICATE_SHA1" bash scripts/build.sh --install
```

If there are multiple matching certificates, the build asks you to choose.
To explicitly make a local ad hoc build, use
`AIRSKIP_SIGN_IDENTITY=- bash scripts/build.sh --install`.

To install elsewhere, set `AIRSKIP_INSTALL_DIR` to an absolute writable directory.
The default is `~/Applications`; `sudo` is not needed.

## Uninstall

Quit AirSkip and remove `~/Applications/AirSkip.app`. Remove its Bluetooth and
Accessibility permissions in System Settings if desired. Use **Forget saved
key** before uninstalling if you also want to remove AirSkip's saved key.
