{{-- Fixture: a literal double quote inside a // comment within a double-quoted
     x-data attribute closes the HTML attribute early. The Alpine object below
     is truncated at the word "answered — every expression on the card
     (selected, toggle, label bindings) then throws "not defined". The audit
     must flag this as a hard break, not a comment-style nit. Real incident
     2026-07-20: a fix agent's $watch comments did exactly this and only a
     browser test caught it. --}}
<div
    x-data="{
        selected: null,
        // null means the question is not "answered" yet, the picker stays hidden
        toggle(value) {
            this.selected = value;
        },
    }"
    class="space-y-2"
>
    <button type="button" x-on:click="toggle(true)" x-bind:aria-pressed="selected === true ? 'true' : 'false'">
        {{ __('shared.yes') }}
    </button>
    <button type="button" x-on:click="toggle(false)" x-bind:aria-pressed="selected === false ? 'true' : 'false'">
        {{ __('shared.no') }}
    </button>
</div>
