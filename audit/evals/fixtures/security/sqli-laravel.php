<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SearchController
{
    public function search(Request $request)
    {
        $term = $request->input('q');
        // BUG: raw SQL with string concatenation -> SQLi
        $results = DB::select("SELECT * FROM products WHERE name LIKE '%" . $term . "%'");

        return view('search.results', ['results' => $results]);
    }
}
