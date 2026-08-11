---
applies_to: [Ll]ogin|[Ll]ogout|[Rr]egist|[Ss]ign[-_]?([Uu]p|[Ii]n)|[Pp]assword|[Ff]orgot|[Vv]erif|[Oo]tp|OTP|[Tt]wo[-_]?[Ff]actor|2fa|2FA|[Cc]heckout|[Cc]art|[Bb]asket|[Pp]ayment|[Bb]illing|[Ss]ubscri|[Pp]romo|[Cc]oupon|[Dd]iscount|[Uu]pload|[Aa]ttachment|[Dd]eactivat|[Dd]elete[-_]?[Aa]ccount|[Aa]ccount[-_]?[Dd]elet|[Ss]upport|[Cc]ontact
priority: recommended
---
# Flow Completeness Guidelines

A user flow is a chain: every step must exist, give feedback, and hand the user to the next step. Dimensional review checks whether the touched step is good; this guideline checks whether the chain is whole. When a file belonging to one of the flows below is in the diff, walk the ENTIRE flow it belongs to — a diff that improves step 3 while step 5 is missing ships a broken chain.

**The core question per flow: where does the user get stuck?** A missing step never appears in the diff, so anchor the finding to the file where the step should attach (the controller, route file, or view that would hand over to it).

**Severity anchor:** `recommended` → findings from this guideline are Minor by default. Escalate to Important only when the missing step strands the user with no way forward or back (dead end), or silently loses their data/money (double payment, lost upload, unconfirmed destructive action).

## I. Authentication Flows

**Login**
- Password-reset entry point visible near the password field, styled as a link.
- Failed login: error names the problem class (wrong credentials) without confirming which field was wrong; the entered identifier survives the error.
- Success: redirect to where the user was headed (intended URL), not unconditionally to a dashboard.

**Sign-up / Registration**
- Requirements (password rules) shown before the first failed attempt, not after.
- Duplicate account attempt: offer login/reset instead of a bare "already exists" error.
- Post-signup state is explicit: verification pending (say so and say where the mail went) or signed in.

**Resetting a password**
- Request step: identifier field (prefill it when the login page already captured it), then an explicit "sent" confirmation that tells the user which channel to check.
- The message/link leads to a page with a new-password field and the password rules visible.
- Expired/used token: a real page explaining it with a re-request action, not a 500 or silent redirect.
- Success step confirms and routes momentum back to login (or signs the user in).

**Verifying an account**
- Unverified state is visible and explains what is blocked until verified.
- Resend action exists, is rate-limited, and confirms it fired.
- Verification landing page confirms success and continues the journey (login or app), never a blank page.

**Two-factor / OTP**
- Code entry offers resend (with cooldown feedback) and a fallback channel or recovery path.
- Wrong code: field is cleared or selected for retry; attempts are limited with a clear lockout message.
- Recovery codes: shown once at setup with an explicit "save these now" step.

## II. Commerce Flows

**Adding to cart**
- The add action gives immediate feedback (cart count, toast, or mini-cart) without tearing the user out of browsing context.
- Out-of-stock/variant-required states are handled at the button, not as a post-submit error.
- The cart is reachable from the confirmation feedback in one step.

**Checkout / Making a payment**
- Order summary (items, costs, fees, total) visible before the pay action, not only after.
- The pay button states the amount and disables + shows progress after the click (double-submit protection is a completeness step, not a nicety).
- Failure: card errors return the user to a correctable state with the cart intact.
- Success: a confirmation page/state with a reference (order number) and the next step (receipt, status link). A redirect to home with a flash message is not a confirmation step.

**Entering a promo code**
- Entry point discoverable at checkout but collapsed (a prominent empty field invites cart abandonment to hunt for codes).
- Applied: the discount is itemized in the summary and the code is removable.
- Invalid/expired: distinct messages; the rest of the checkout state survives.

**Canceling a subscription**
- The path to cancel is findable from billing/settings (a support-ticket-only cancellation is a dead end finding, Important).
- Consequences stated before confirming: end date, what access remains, what happens to data.
- Confirmation step, then an explicit "canceled" state showing until when access lasts, plus resubscribe path.

## III. Data & Form Flows

**Submitting a form**
- Submit disables + indicates progress; double submission is prevented.
- Validation errors: summarized near the submit action AND marked at the field; entered values survive.
- Success: explicit confirmation state; for multi-step forms, progress is visible and back navigation does not lose entered data.

**Showing input errors**
- Error appears at the field, in text (not color alone), and says how to fix it, not just that it is wrong.
- Timing: validate on blur or submit — not on first keystroke.
- Error state clears when the input becomes valid, not only on resubmit.

**Uploading media**
- Constraints (type, size) stated before choosing a file; violations rejected client-side with a message, not by server error.
- Progress indication for anything beyond instant; cancel exists for long uploads.
- Failure keeps surrounding form state; retry does not require re-picking the file if avoidable.
- Success shows the uploaded item (preview/name) with a remove/replace action.

**Saving changes**
- Explicit save: unsaved-changes state is visible and navigating away warns. Auto-save: the "saved" moment is communicated.
- Save failure surfaces an error and preserves the edits; silent failure is a data-loss finding (Important).

**Filtering items**
- Active filters are visible as removable state; a clear-all exists with several active.
- Zero-result state says the filters caused it and offers reset — distinct from the general empty state.
- Filters survive navigation to detail and back (losing them makes users redo work).

## IV. Account & Support Flows

**Deleting an account**
- Consequences enumerated before confirming (what is deleted, what is retained and why, deadlines).
- Confirmation requires a deliberate act (re-auth or typed confirmation) — a single click is incomplete for an irreversible action.
- After deletion: sign-out to an explicit "deleted" confirmation, not an error page. Grace-period recovery, if any, is stated.

**Contacting support**
- The contact path is reachable from error and dead-end states, not only the footer.
- The form states the expected response channel and time; success confirms with a reference (ticket ID or echo mail).
- Context the app already has (account, plan, current page) is attached automatically rather than asked again.
