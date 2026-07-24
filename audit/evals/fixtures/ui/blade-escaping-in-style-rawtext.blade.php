{{-- Mail shell: shared HTML frame for all transactional mails. --}}
<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ config('app.name') }}</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            background-color: #f4f4f5;
            font-family: {{ config('mail.font_stack', '"Helvetica Neue", Helvetica, Arial, sans-serif') }};
            color: #18181b;
        }
        .wrapper { max-width: 600px; margin: 0 auto; padding: 24px; }
        .card { background: #ffffff; border-radius: 8px; padding: 32px; }
        .footer { font-size: 12px; color: #71717a; padding-top: 16px; }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="card">
            {{ $slot }}
        </div>
        <div class="footer">
            {{ config('app.name') }} &middot; <a href="{{ config('app.url') }}">{{ config('app.url') }}</a>
        </div>
    </div>
</body>
</html>
