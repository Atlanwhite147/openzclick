# Multicast on iOS

The network publication uses mDNS, which is multicast traffic. Android, Windows,
macOS and Linux allow it; iOS restricts it to applications that hold the
`com.apple.developer.networking.multicast` entitlement, which Apple grants case
by case.

## State of the repository

`app/ios/Runner/Runner.entitlements` contains the entitlement, but the Xcode
project does **not** reference it. This is deliberate: a provisioning profile
without the entitlement fails to sign, so the continuous build would break for
everyone before Apple answers.

## Requesting it

1. Sign in to the Apple developer portal with a paid account.
2. Open the request form for the multicast entitlement and describe the use
   case: the application announces a local service with DNS-SD so that a
   training application running on the same network can find it.
3. Wait for the approval, which also has to be enabled on the App ID.

## Wiring it

Once approved:

1. In Xcode, select the Runner target, *Signing & Capabilities*, and add the
   entitlement file.
2. Check that the App ID in the developer portal shows the multicast capability.
3. Rebuild: the advertisement now works from the phone, and the same code that
   already runs on the other platforms needs no change.

## Without the entitlement

The application still works on iPhone for everything else: pairing the
controller, gears, gestures and diagnostics. Only the announcement is silent.
Use the tap injection path or an Android device as the bridge in the meantime.
