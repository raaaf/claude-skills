# Surface Taxonomy

Used by design-audit Phase 1.5 (surface coverage): the mapping agent matches the project's routes and views against this list, then reports which surfaces exist and which are missing but expected. Taxonomy after checklist.design (surface names only; all descriptions are our own words).

## TOC

- Expectation rules (read first)
- I. Website (marketing / public pages)
- II. Web App (product surfaces)
- III. Mobile App (native surfaces)
- IV. Flows (multi-step journeys)

## Expectation rules (read first)

- A surface is MISSING only when the app's domain clearly calls for it: no cart without commerce, no paywall without subscriptions, no map view without location data. Uncertain → omit; this stage feeds Elevation, and elevation must be convincing or absent.
- **Cross-cutting set, expected of almost every app of its platform class:** 404 (web), Empty state, Login (if there are accounts), Settings/Account (if there are accounts), Showing input error (if there are forms), Contact/Support path. Absence of these needs no domain justification.
- Websites get section I, web apps section II, native apps section III; section IV (flows) applies wherever the corresponding feature exists, regardless of platform.
- Match on function, not naming: a "profile" route can cover Account; a modal can cover a whole surface. One file can host several surfaces, one surface can span several files.

## I. Website (marketing / public pages)

| Surface | What it is |
|---|---|
| Home | The landing surface that states what the product is and routes visitors onward |
| Pricing | Plan comparison with a clear action per plan |
| Features | What the product does, shown per capability |
| About | Who is behind the product and why |
| Team | The people, with roles |
| Careers | Open roles and how to apply |
| Blog | Index of posts |
| Blog post | Single article layout |
| Press / Media | Assets and facts for journalists |
| Testimonials | Social proof from named customers |
| Compare | Product vs. named alternatives |
| FAQ | Recurring questions answered on one page |
| Contact | A way to reach a human |
| Support / Help entry | Where to get help before or after buying |
| Sign up | Account creation entry for the public |
| Login | Session entry for returning users |
| Waitlist | Pre-launch email capture with expectation setting |
| Search | Site-wide content search |
| Cart | Pending purchase overview (commerce sites) |
| Billing | Purchase/payment management for customers |
| Status | Live service health, incidents, history |
| Security | How customer data is protected (trust page) |
| Privacy / Legal | Privacy policy, terms, imprint |
| Affiliate | Partner/referral program terms and signup |
| 404 | Not-found page that routes the user back |

## II. Web App (product surfaces)

| Surface | What it is |
|---|---|
| Login | Session entry incl. errors and reset entry point |
| 2FA | Second-factor challenge and setup |
| Onboarding | First-run guidance to the first success moment |
| Empty state | What a list/screen shows before it has data |
| Settings | User-scoped preferences |
| Account | Identity, credentials, danger zone |
| Notification settings | Per-channel, per-event opt-in/out |
| Notifications | In-product inbox of events |
| Billing | Plan, invoices, payment method |
| Pricing / Upgrade | In-product plan change surface |
| Admin panel | Operator view over users/content |
| User management | Invite, roles, deactivate members |
| Public profile | User's outward-facing page |
| Feed | Stream of activity or content |
| Single item detail | One record with its actions and history |
| Search results | Query results with refinement |
| Analytics | Charts/metrics over the user's data |
| Timeline / Gantt | Time-axis view of items |
| Kanban board | Column/status view of items |
| Multi-step form | Wizard with progress and safe back navigation |
| Comments | Threaded discussion on an item |
| Version history | Past states of an item, restorable |
| Integrations | Connect/disconnect third-party services |
| API keys | Create, scope, reveal-once, revoke keys |
| Help center | In-product self-service docs |
| Chat | Real-time conversation surface |
| Maintenance | Planned-downtime page that keeps trust |

## III. Mobile App (native surfaces)

| Surface | What it is |
|---|---|
| Splash screen | Launch state that hands off fast |
| Onboarding | First-run value explanation and permissions priming |
| Onboarding checklist | Persistent early-task list toward activation |
| Login | Session entry incl. biometric/SSO options |
| Account | Identity and danger zone on small screens |
| Settings | Preferences following platform idioms |
| Tab bar navigation | Primary sections, 3-5 tabs |
| Gesture navigation | Swipe/back gestures without conflicts |
| Action sheet | Contextual action list from the bottom |
| In-app notifications | Notification display and deep-link handling |
| Paywall | Subscription offer with price, terms, restore |
| Billing | Store-mediated purchase management |
| Checkout | Purchase completion on mobile |
| Cart | Pending purchase overview on mobile |
| Search | Query input, suggestions, results on mobile |
| Camera / media capture | In-app capture with permission handling |
| Map view | Location display with clustering and detail |
| Chat | Mobile conversation with keyboard handling |
| In-app browser | External links without losing the user |
| Invite | Sharing/referral of the app |

## IV. Flows (multi-step journeys)

| Flow | Chain in one line |
|---|---|
| Resetting password | Entry near password field → verify identity → sent confirmation → new-password page → success into login |
| Verifying account | Visible unverified state → resend option → landing page confirming → journey continues |
| Submitting a form | Progress on submit → double-submit protection → field-level errors preserving input → explicit success |
| Showing input error | At the field, in text, actionable, clearing when fixed |
| Saving changes | Unsaved-state visibility → save feedback → failure preserves edits |
| Uploading media | Constraints upfront → progress + cancel → failure keeps state → preview with remove |
| Filtering items | Visible removable filter state → distinct zero-result state → filters survive navigation |
| Adding to cart | Immediate feedback in context → stock/variant handling at the button → one step to cart |
| Making a payment | Summary before pay → amount on the button → correctable failure → confirmation with reference |
| Entering promo code | Collapsed entry → itemized discount, removable → distinct invalid/expired messages |
| Canceling subscription | Findable path → consequences stated → confirmation → end-date state + resubscribe |
| Deleting account | Consequences enumerated → deliberate confirmation → explicit deleted state |
| Contacting support | Reachable from dead ends → expectation setting → confirmation with reference |
