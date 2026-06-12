// BUG: Alpine.data() called directly at module top-level.
// Alpine may not be initialized yet when this module loads,
// causing "Alpine is not defined" errors at runtime.
Alpine.data('toastManager', () => ({
    toasts: [],
    add(message) {
        this.toasts.push({ id: Date.now(), message });
    },
    remove(id) {
        this.toasts = this.toasts.filter(t => t.id !== id);
    },
}));
