# Apple CarPlay Video Entitlement Application Form Guide

When applying for the **CarPlay Video Entitlement** via Apple Developer Portal ([https://developer.apple.com/contact/carplay/](https://developer.apple.com/contact/carplay/)), use the structured information below:

---

### Basic Information
- **Organization / Developer Name:** [Your Name / Org]
- **Developer Account Team ID:** [Your Team ID]
- **App Name:** Mivu
- **Bundle Identifier:** `com.kelvinsze.mivu` (or your chosen Bundle ID)
- **App Category:** Video

---

### Entitlement Application Description (English)

```text
Mivu is a lightweight local-network video player and media receiver designed for user-selected media. It supports HTTP/HTTPS video playback, HLS (.m3u8) streams, standards-compliant local-network media casting (UPnP/DLNA), and personal media streaming.

On supported CarPlay systems featuring "Video in Car", Mivu allows users to play their selected video content strictly when the vehicle indicates that video playback is safely available (e.g., when the vehicle is parked).

Safety and System Compliance:
- Mivu relies entirely on the native Apple CarPlay framework and the vehicle's system state (CPSessionConfiguration / video playback availability) to determine if video can be displayed.
- It does not attempt to spoof vehicle state, bypass driving safety restrictions, or enable video playback while the vehicle is in motion.
- When the vehicle transitions to a restricted state, Mivu immediately adheres to CarPlay guidelines by stopping or adapting video output.
- Mivu also natively supports AirPlay video streaming from its iOS playback interface.

Primary Use Case:
Allowing users to view their personal videos and cast media onto their CarPlay vehicle screen while parked at rest stops or charging stations.
```

---

### Follow-up / Additional Questions Apple May Ask

1. **How is video content sourced?**
   > Content is strictly user-provided through direct URL entry, local network UPnP/DLNA casting from the user's own devices on the same local network, or the user's personal media server. Mivu does not host or scrape unauthorized proprietary streaming content.

2. **How does Mivu handle driving safety?**
   > Mivu obeys `CPSessionConfiguration.supportsVideoPlayback`. Video rendering is only engaged when the CarPlay session explicitly reports that the vehicle allows video presentation. If the vehicle moves or disables video, Mivu suspends video output without any attempt to bypass system restrictions.

3. **Distribution Type:**
   > Development / Ad Hoc testing for personal vehicle validation (e.g., Infiniti Q50L CarPlay test environment).
