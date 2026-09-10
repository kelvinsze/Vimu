# Apple Multicast Networking Entitlement Application Form Guide

When applying for the **Multicast Networking Entitlement** (`com.apple.developer.networking.multicast`) via Apple Developer Portal ([https://developer.apple.com/contact/request/networking-multicast](https://developer.apple.com/contact/request/networking-multicast)), use the structured information below:

---

### Basic Information
- **App Name:** Mivu
- **Bundle Identifier:** `com.kelvinsze.mivu` (or your chosen Bundle ID)
- **Primary Category:** Media / Utilities

---

### Justification & Technical Description (English)

```text
Mivu implements a standards-compliant UPnP/DLNA MediaRenderer designed to receive user-initiated video casting streams over the local Wi-Fi network.

Technical Requirement for Multicast:
- Standard UPnP Simple Service Discovery Protocol (SSDP) operates over UDP Multicast address 239.255.255.250 on port 1900.
- To be discovered as a media renderer by UPnP/DLNA controllers (such as local video apps, media servers, and mobile clients), Mivu must listen for SSDP M-SEARCH multicast discovery queries and broadcast periodic SSDP NOTIFY announcements on the local subnet.
- Without the multicast networking entitlement, incoming UDP multicast discovery packets are filtered by iOS, preventing standard DLNA controllers on the local network from discovering Mivu.

Privacy & Security Scope:
- Multicast is used strictly on the local Wi-Fi network for local device discovery and UPnP renderer control.
- Mivu does not use multicast for advertising, telemetry, user tracking, or any internet-facing communication.
- No personal user data is broadcast over multicast.
```

---

### Info.plist Configuration
Ensure your `Info.plist` also contains:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Mivu uses your local network to discover media servers and receive video casting requests from devices and apps on your network.</string>
```
