# Privacy Policy for Mivu

*Effective Date: August 20, 2026*

Mivu ("we", "our", or "the app") is committed to respecting and protecting your privacy. This Privacy Policy explains how Mivu operates regarding data collection, transmission, and local network usage.

---

### 1. Zero Data Collection
Mivu is designed with privacy at its core:
- **No Personal Data Collection:** We do not collect, store, or transmit your personal identifiable information (PII), device identifiers, or contact details.
- **No Analytics / Telemetry:** Mivu does not integrate third-party tracking SDKs, analytics services, or advertising frameworks.
- **No Account Required:** You can use all features of Mivu without registering an account or providing an email address.

---

### 2. Local Network Usage
Mivu requests access to your **Local Network** (`NSLocalNetworkUsageDescription`) strictly for the following purposes:
- **Device Discovery & Casting:** To listen for and respond to UPnP/DLNA casting requests initiated by other media applications on your local Wi-Fi network.
- **Media Streaming:** To receive video URLs and stream media content directly across your local network from your personal media devices or user-entered endpoints.
- **Multicast Discovery:** Standard UPnP/DLNA protocols utilize UDP multicast (`239.255.255.250:1900`) for SSDP discovery solely within your local area network.

Local network communication remains entirely within your local Wi-Fi / LAN environment and is never uploaded to any remote server.

---

### 3. Media Content & Playback
- Video streams and URLs played through Mivu are accessed directly from the provided source or server.
- Playback history is stored locally on your device using on-device storage and is never uploaded to external servers.

---

### 4. CarPlay Compliance
When connected to Apple CarPlay:
- Mivu strictly obeys CarPlay system state and driving safety regulations.
- Video playback is rendered only when allowed by the vehicle operating system (e.g. while parked).
- Mivu does not collect vehicle telemetry or driver behavioral data.

---

### 5. Contact Us
If you have any questions or feedback regarding this Privacy Policy or Mivu's privacy practices, please contact us at:
- **Email:** support@mivu.app (or your developer email)
- **Repository:** https://github.com/kelvinsze/Mivu
