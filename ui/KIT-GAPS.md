# Kit gaps found while building the Pointroo mockups

Each gap names the stand-in the mockups use today. The app draws none of these itself. G0 to G10 come from the UX spec
(section 7). G11 and up are new, found while building.

| # | Gap | Needed by | Stand-in in the mockups |
|---|---|---|---|
| G0 | Brand layer `brands/pointroo.css` and `pointroo` in `BRAND_NAMES` | every screen | `oneroo` brand (spec question 1) |
| G1 | RooNoticeCard: card for an app-owned floating panel (surface, radius, shadow, head, media row, actions, "+N", hover pauses the timer) | notice (done with images, question) | `parts/FloatingSurface.vue` (kit tokens only); RooToast for the text-only done notice |
| G2 | Icons `mic`, `reply`, `message-circle-question`, `monitor` | pill, notice, set up | `circle-help`, `send`, `image` |
| G3 | RooStateMark state `recording` (the one red dot that may pulse) | pill | RooStateMark `err` with the word "Recording" hidden visually |
| G4 | RooThumb: image tile, fixed aspect, number chip, click or Space opens the full image, alt text required, list-row tile size | list rows, crops, notice | RooIcon `image` in the row tile; crop rows are RooListRow with a RooChip number |
| G5 | Image pair "Before" / "Screen now" | notice, detail | two RooListRow rows with an image icon (detail); text only (RooToast) |
| G6 | HUD surface for a tiny always-on-top strip (height 44, radius, shadow, drag area) | recording pill | `parts/FloatingSurface.vue` |
| G7 | Group head for a content list (RooSidebarGroup is for sidebars) | list groups | RooSidebarGroup `placement="sidebar"` |
| G8 | Media frame: muted looping video with poster and pause button, still under reduced motion | How it works | RooHowItWorks default example rows only (no loop) |
| G9 | RooMeta is 11px, under the 12px family floor | meta text | 12px muted text through RooListRow subtitle |
| G10 | RooSwitcher inline with a visible heading line | picker | a heading above an open RooSwitcher; `label` is aria only |

## New gaps from the build

| # | Gap | Where | What the mockup does |
|---|---|---|---|
| G11 | `@roo/kit/static.css` has `.roo-static-card` (surface, card radius, card shadow), but an app that uses the real kit CSS does not get it. There is no kit class or component for "a floating surface" in app code | pill, notices, menu bar menu | `parts/FloatingSurface.vue` copies the three declarations with tokens |
| G12 | RooSwitcher number keys are Cmd+1 to 9 (`shortcuts`), the picker needs plain 1 to 9 because the panel has no other input | picker | `shortcuts` on, so rows show a Cmd digit; Swift must handle plain digits |
| G13 | Kit style `:global(.roo-force-reduced) .roo-icon-button-fill, :global([data-motion='still']) .roo-icon-button-fill` in RooIconButton.vue compiles (Vue 3.5.46 here) to `.roo-force-reduced, [data-motion='still'] { display: none }`, which hides the whole page in any still-motion shell (the family mockups shell is one). Fix in the kit: write each selector as one `:global(...)` | every frame with the mockups shell | `ui/scripts/mockups.mjs` rewrites those two selectors while it builds. Drop it when the kit is fixed. oneroo lock pins vue 3.5.45; installing that here failed (see report) |
| G14 | No window-button (traffic light) stand-in for review frames. RooBar leaves a 92px inset but nothing draws the buttons | main window frames | `parts/TrafficLights.vue`, three neutral circles on kit tokens |
| G15 | RooSplit sheet has no visible close or back control, only Esc | narrow main window (detail as a sheet) | none; the frame shows the sheet as it is |
| G16 | No native menu (NSMenu) mock part | menu bar menu | RooListRow rows with RooKbd on a floating surface; titles as RooBarChip |
| G17 | RooStateMark has no way to hide its word while keeping it for screen readers | pill dot | a scoped rule hides `.roo-state-mark-label` in the pill; a prop (`hideLabel`) would be cleaner |
| G18 | RooLiveDot always shows its word, so a sidebar row cannot show only the dot (spec: word as tooltip only) | sidebar rows | the word shows next to the dot |
| G19 | RooInput has no `hideLabel` (RooSelect has); a visible label cannot be skipped | port row, question input | `aria-label` and no `label` prop |
