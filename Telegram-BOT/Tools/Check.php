<?php
declare(strict_types=1);

/**
 * Offline self-check for the bot: no database, no network, no Telegram.
 *
 * Run it before deploying:
 *
 *     php Tools/check.php
 *
 * It answers the questions that used to need a live bot to notice:
 *   • does every file parse and does every class load
 *   • does every inline button the bot draws lead somewhere the dispatcher
 *     answers (a dead «بازگشت» button is invisible until somebody taps it)
 *   • does every handler in the route table exist
 *   • is a method defined twice
 *   • does every SQL statement name a table the schema creates
 *   • is any file still referencing a helper that was removed
 *
 * Exit code is 0 when everything passes, 1 when something would break at
 * runtime. Nothing here writes to the database.
 */

if (PHP_SAPI !== 'cli') {
    header('Content-Type: text/html; charset=utf-8');
    http_response_code(200);
    echo '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>Umbrella — check</title></head><body style="font-family:Tahoma,sans-serif;max-width:620px;margin:70px auto;line-height:2.1"><h2>&#128270; این ابزار از خط فرمان اجرا می‌شود</h2><p>check.php گزارش خودآزمایی ربات را در ترمینال چاپ می‌کند (نحو فایل‌ها، کلاس‌ها، دکمه‌ها، مسیرها و کوئری‌ها) و هیچ خروجی وبی تولید نمی‌کند.</p><pre style="background:#16191f;color:#e8e8e8;padding:12px 14px;border-radius:8px;direction:ltr;text-align:left">php Tools/check.php</pre><p>برای تست ربات روی سرور از طریق وب، <code>index.php?AppApi=app/diag</code> را باز کنید.</p></body></html>';
    exit;
}

define('ROOT', (string)realpath(__DIR__ . '/..'));

$Errors = [];
$Warnings = [];
$Checked = ['files' => 0, 'callbacks' => 0, 'routes' => 0, 'queries' => 0];

/** @return list<string> */
function phpFiles(string $Root): array
{
    $Out = [];
    $Iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($Root, FilesystemIterator::SKIP_DOTS)
    );

    foreach ($Iterator as $File) {
        if (!$File instanceof SplFileInfo) continue;
        if ($File->getExtension() !== 'php') continue;
        if (str_contains($File->getPathname(), DIRECTORY_SEPARATOR . 'Tools' . DIRECTORY_SEPARATOR)) continue;
        $Out[] = $File->getPathname();
    }

    sort($Out);

    return $Out;
}

$Files = phpFiles(ROOT);

// The install schema is plain SQL and is the authority on which tables exist;
// the table check below reads it as well as the runtime table map in PHP.
$SqlSchemaPath = ROOT . '/Database/Schema.SQL';
$SqlSchemaSource = is_file($SqlSchemaPath) ? (string)file_get_contents($SqlSchemaPath) : '';

// ── 1. syntax ────────────────────────────────────────────────────────────────
$Sources = [];

foreach ($Files as $File) {
    $Checked['files']++;
    $Source = (string)file_get_contents($File);
    $Sources[$File] = $Source;

    try {
        // token_get_all() parses the file the same way the engine does; a syntax
        // error surfaces as a ParseError from the surrounding try in PHP 8.
        token_get_all($Source, TOKEN_PARSE);
    }

    catch (Throwable $Error) {
        $Errors[] = relative($File) . ': ' . $Error->getMessage();
    }
}

function relative(string $Path): string
{
    return ltrim(str_replace(ROOT, '', $Path), '/\\');
}

/** @var array<string, array{file: string, methods: array<string, true>}> $Classes */
$Classes = [];

foreach ($Sources as $File => $Source) {
    preg_match_all('/(?:final\s+|abstract\s+|readonly\s+)*class\s+(\w+)/i', $Source, $Matches);
    $Names = $Matches[1];

    preg_match_all('~function\s+(\w+)\s*\(~', $Source, $Matches);
    $Methods = $Matches[1];

    $Twice = array_filter(array_count_values($Methods), static fn(int $N): bool => $N > 1);

    foreach (array_keys($Twice) as $Name) {
        $Errors[] = relative($File) . ": method {$Name}() is defined more than once";
    }

    foreach ($Names as $Name) {
        if (isset($Classes[$Name])) {
            $Errors[] = relative($File) . ": class {$Name} is declared twice";
            continue;
        }

        $Classes[$Name] = [
            'file' => relative($File),
            'methods' => array_fill_keys($Methods, true),
        ];
    }
}

// ── 3. every callback the bot draws is answered by the dispatcher ────────────
$DispatcherPath = (string)realpath(ROOT . '/Bot/Dispatcher.php');
$Dispatcher = $Sources[$DispatcherPath] ?? '';
$Keys = [];
$Prefixes = [];

// Route table + match() arms: 'label' => SomeFlow::method(
preg_match_all(
    "/'([^']*)'\s*=>\s*(?:\[)?(?:AdminFlow|UserFlow|SubscriptionFlow|ProfileFlow|AppFlow)::/u",
    $Dispatcher,
    $Matches
);
$Keys = array_fill_keys($Matches[1], true);

// startswith() routing for the parametrised callbacks (ticket_view:…, …)
preg_match_all("/str_starts_with\(\s*\\\$Data\s*,\s*'([^']*)'\s*\)/u", $Dispatcher, $Matches);
$Prefixes = $Matches[1];

// The two spellings of «start» are handled by their own branch.
$Keys['start'] = true;
$Keys['/start'] = true;

foreach ($Sources as $File => $Source) {
    preg_match_all("/'callback_data'\s*=>\s*'([^']*)'/u", $Source, $Matches);

    foreach ($Matches[1] as $Callback) {
        $Checked['callbacks']++;
        if (isset($Keys[$Callback])) continue;

        $Answered = false;

        foreach ($Prefixes as $Prefix) {
            if (str_starts_with($Callback, $Prefix)) {
                $Answered = true;
                break;
            }
        }

        if (!$Answered) {
            $Errors[] = relative($File) . ": button «{$Callback}» has no handler in Dispatcher";
        }
    }
}

// ── 4. every routed method exists ────────────────────────────────────────────
preg_match_all(
    "/\[(AdminFlow|UserFlow|SubscriptionFlow|ProfileFlow|AppFlow)::class,\s*'(\w+)'\]/",
    $Dispatcher,
    $Matches,
    PREG_SET_ORDER
);

foreach ($Matches as $Match) {
    $Checked['routes']++;
    $Class = $Match[1];
    $Method = $Match[2];

    if (!isset($Classes[$Class])) {
        $Errors[] = "Dispatcher routes {$Class}::{$Method}() but class {$Class} does not exist";
        continue;
    }

    if (!isset($Classes[$Class]['methods'][$Method])) {
        $Errors[] = "Dispatcher routes {$Class}::{$Method}() but that method does not exist";
    }
}

// Every flow referenced anywhere must be a class this codebase declares.
$AllSource = implode("\n", $Sources);
preg_match_all('/\b(AdminFlow|UserFlow|SubscriptionFlow|ProfileFlow|AppFlow)\s*::/', $AllSource, $Matches);

foreach (array_unique($Matches[1]) as $Class) {
    if (!isset($Classes[$Class])) {
        $Errors[] = "references {$Class} but that class does not exist";
    }
}

// ── 5. SQL table names are created by the schema ─────────────────────────────
// Two sources: the install script (plain SQL) and the runtime table map.
$SchemaNames = [];
$SchemaSource = $SqlSchemaSource;

foreach ($Sources as $Body) {
    if (str_contains($Body, 'CREATE TABLE')) $SchemaSource .= "\n" . $Body;
}

preg_match_all('~CREATE TABLE(?: IF NOT EXISTS)?\s+`?(\w+)`?~i', $SchemaSource, $Matches);

foreach ($Matches[1] as $Table) {
    $SchemaNames[strtolower($Table)] = true;
}

if ($SchemaNames !== []) {
    foreach ($Sources as $File => $Body) {
        // Only the SQL inside the code, with the two constructs that put a
        // column name right after a keyword removed: an upsert clause and the
        // column list of an INSERT.
        $Query = preg_replace('~ON\s+DUPLICATE\s+KEY\s+UPDATE.*~is', '', $Body) ?? $Body;
        $Query = preg_replace('~\`?\w+\`?\s*\([^()]*\)~s', '', $Query) ?? $Query;

        preg_match_all('~\b(?:FROM|INTO|UPDATE|JOIN)\s+`(\w+)`~i', $Query, $Matches);

        foreach (array_unique($Matches[1]) as $Table) {
            $Checked['queries']++;
            $Key = strtolower($Table);

            if (isset($SchemaNames[$Key])) continue;

            $Warnings[] = relative($File) . ": query names `{$Table}` as a table, but no schema creates it";
        }
    }
}

// ── 6. no leftover references to helpers that no longer exist ────────────────
$Hosts = ['Helper', 'Common', 'ServerClient', 'PanelClient', 'TelegramClient', 'Repository', 'Schema', 'AppFilter'];

foreach ($Hosts as $Class) {
    if (!isset($Classes[$Class])) continue;

    preg_match_all('/\b' . $Class . '::(\w+)\s*\(/', $AllSource, $Matches);

    foreach (array_unique($Matches[1]) as $Method) {
        if (!isset($Classes[$Class]['methods'][$Method])) {
            $Errors[] = "{$Class}::{$Method}() is called but not defined in {$Class}";
        }
    }
}

// ── report ───────────────────────────────────────────────────────────────────
$Line = static fn(string $Text): string => $Text . PHP_EOL;

echo $Line('Umbrella bot — offline check');
echo $Line(str_repeat('─', 34));
echo $Line(sprintf('files      %d', $Checked['files']));
echo $Line(sprintf('callbacks  %d', $Checked['callbacks']));
echo $Line(sprintf('routes     %d', $Checked['routes']));
echo $Line(sprintf('queries    %d', $Checked['queries']));
echo $Line('');

foreach ($Errors as $Error) {
    echo $Line('✖ ' . $Error);
}

foreach ($Warnings as $Warning) {
    echo $Line('! ' . $Warning);
}

if ($Errors === []) {
    echo $Line('✔ no blocking problem found');
}

echo $Line('');
echo $Line(sprintf('errors: %d, warnings: %d', count($Errors), count($Warnings)));

exit($Errors === [] ? 0 : 1);
