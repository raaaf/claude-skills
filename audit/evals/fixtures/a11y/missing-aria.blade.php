<div class="modal" style="display: block;">
    <div class="modal-content">
        {{-- BUG: dialog without role, aria-modal, or labelled-by --}}
        <h2>Delete account?</h2>
        <p>This cannot be undone.</p>

        {{-- BUG: icon-only buttons without aria-label --}}
        <button class="btn-close" onclick="closeModal()">
            <svg width="24" height="24"><path d="..."/></svg>
        </button>

        <button class="btn-confirm" onclick="confirmDelete()">
            <svg width="24" height="24"><path d="..."/></svg>
        </button>
    </div>
</div>
