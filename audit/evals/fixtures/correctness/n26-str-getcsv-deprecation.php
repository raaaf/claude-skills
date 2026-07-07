<?php

namespace App\Services\CsvParser;

class N26Parser implements CsvParserInterface
{
    public function parse(string $path): array
    {
        $rows = [];
        $handle = fopen($path, 'r');

        while (($line = fgets($handle)) !== false) {
            // BUG: str_getcsv() called without the escape parameter. PHP 8.4
            // deprecates relying on the default backslash-escape behavior
            // (E_DEPRECATED) and it silently mangles descriptions/amounts
            // containing a trailing backslash. Pass '' explicitly:
            // str_getcsv($line, ',', '"', '').
            $rows[] = str_getcsv($line, ',', '"');
        }

        fclose($handle);

        return $rows;
    }
}
