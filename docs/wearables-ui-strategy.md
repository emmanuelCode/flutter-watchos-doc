# Future Horizon: Decoupled Wearables (watchOS & Wear OS)

> **Out of scope for the watchOS embedder spec.** Extracted from [flutter_watchos_architecture.md](../flutter_watchos_architecture.md).

While this specification focuses strictly on standalone watchOS via an embedder, its UI architectural principles are designed to align with broader wearable platforms without forcing lowest-common-denominator compromises.

Today, Flutter already executes on **Wear OS** because Wear OS is built on the standard Android runtime (AOSP). However, wearable UI and hardware interaction diverge fundamentally from phones. Rather than proposing a single compromise wearable widget library, this architecture favors Flutter's proven decoupling pattern (`material` vs. `cupertino`):

```text
                  [ Flutter Widgets / dart:ui ]
                               │
       ┌───────────────────────┴───────────────────────┐
       ▼                                               ▼
 [ watchos_ui ]                                 [ wearos_ui ]
 • Apple HIG (SF Compact)                       • Material You for Wear OS
 • Rectangular/Squircle layouts                 • Circular layouts & curved text
 • Digital Crown scroll physics                 • Rotary dial scroll physics
 • Apple Taptic detents                         • Android haptic feedback
 • OLED & Low-Power lints                       • OLED & Ambient Mode lints
```
* **`watchos_ui` (Primary focus of this spec):** Encodes Apple's watchOS Human Interface Guidelines (SF Compact typography, squircle screen geometry, Digital Crown physics).
* **`wearos_ui` (Conceptual / community target):** Encodes Google's Wear OS Material guidelines (circular layouts, curved text along the bezel, modern rotary scroll mechanics).

Both layers sit on Flutter's core `widgets` layer and share common wearable disciplines: prioritizing true-black or high-contrast dark surfaces for OLED efficiency, pausing animation ticks when idle, and handling ambient display transitions. Platform hardware variations (HealthKit vs. Android Health Services, audio session routing) remain within the domain of standard federated plugins rather than the embedder.
