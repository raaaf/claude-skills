<?php

namespace App\Providers;

class SvgUploadProvider
{
    public function register(): void
    {
        add_filter('upload_mimes', [$this, 'allowSvg']);
        add_filter('wp_handle_upload_prefilter', [$this, 'guardSvgUpload']);
    }

    // SVG uploads are enabled for every role that can upload media.
    public function allowSvg(array $mimes): array
    {
        $mimes['svg'] = 'image/svg+xml';

        return $mimes;
    }

    public function guardSvgUpload(array $file): array
    {
        if ($file['type'] === 'image/svg+xml') {
            if (! current_user_can('manage_options')) {
                $file['error'] = 'Only administrators may upload SVG files.';

                return $file;
            }

            $this->sanitize($file['tmp_name']);
        }

        return $file;
    }

    private function sanitize(string $path): void
    {
        $svg = file_get_contents($path);
        $svg = preg_replace('#<script\b.*?</script>#is', '', $svg);
        file_put_contents($path, $svg);
    }
}
