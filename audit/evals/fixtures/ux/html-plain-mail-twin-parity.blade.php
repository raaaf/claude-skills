{{-- HTML mail footer partial.
     KEEP IN SYNC with the plain-text twins: every mail also renders a
     text part via resources/views/emails/text/*.blade.php (16 files),
     each carrying this footer as plain text. --}}
<tr>
    <td class="footer" style="font-size: 12px; color: #71717a; padding: 16px 32px;">
        <p style="margin: 0 0 4px 0;">{{ config('app.name') }}</p>
        {{-- Footer link target changed in this diff: the old target /einstellungen/mail
             was replaced by the new notification centre. The 16 plain-text twins under
             emails/text/ still link to /einstellungen/mail. --}}
        <p style="margin: 0;">
            <a href="{{ route('notifications.settings') }}" style="color: #71717a;">
                {{ __('mail.manage_notifications') }}
            </a>
        </p>
    </td>
</tr>
