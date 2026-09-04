{{-- Mobile navigation. The x-show directive used to sit on the <nav>; a layout
     refactor moved it to the wrapping <div> so the backdrop fades together with
     the menu. The focus-trap script below still queries `nav[x-show]` and now
     finds nothing, so Tab leaves the open menu. The existing Vitest spec
     (mobile-nav.test.ts) only asserts isOpen/toggle() and stays green. --}}
<div x-data="mobileNav" x-show="isOpen" x-cloak class="fixed inset-0 z-50 bg-black/40">
    <nav id="mobile-nav" aria-label="Hauptmenü" class="ml-auto h-full w-80 bg-white p-6">
        <button type="button" @click="toggle()" aria-label="Menü schließen">×</button>
        <ul>
            @foreach ($items as $item)
                <li><a href="{{ $item['url'] }}">{{ $item['label'] }}</a></li>
            @endforeach
        </ul>
    </nav>
</div>

<script nonce="{{ $cspNonce }}">
document.addEventListener('alpine:init', () => {
    Alpine.data('mobileNav', () => ({
        isOpen: false,
        toggle() {
            this.isOpen = !this.isOpen;
            if (this.isOpen) this.$nextTick(() => this.trapFocus());
        },
        trapFocus() {
            const panel = this.$el.querySelector('nav[x-show]');
            if (!panel) return;
            const focusable = panel.querySelectorAll('a[href], button:not([disabled])');
            const first = focusable[0], last = focusable[focusable.length - 1];
            first?.focus();
            panel.addEventListener('keydown', (e) => {
                if (e.key !== 'Tab') return;
                if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
                else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
            });
        },
    }));
});
</script>
