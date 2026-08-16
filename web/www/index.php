<?php
declare(strict_types=1);

/*
 * Nostalgia - lokale Verwaltungsseite
 *
 * Diese Seite ist absichtlich nur auf dem eigenen Rechner erreichbar. Sie
 * erstellt Vanilla-kompatible SRP6-Konten und verwaltet .pdump-Dateien, die
 * durch die vorhandenen Befehle .x save und .x load verarbeitet werden.
 */

// Keep the session data beside this page so the packaged web server works
// independently of any system-wide PHP or Laragon configuration.
$sessionDirectory = __DIR__ . DIRECTORY_SEPARATOR . 'sessions';
if (!is_dir($sessionDirectory) && !mkdir($sessionDirectory, 0700, true) && !is_dir($sessionDirectory)) {
    http_response_code(500);
    exit('Der Ordner fuer Web-Sitzungen konnte nicht erstellt werden.');
}
ini_set('session.save_path', $sessionDirectory);
session_start();

$remoteAddress = $_SERVER['REMOTE_ADDR'] ?? '';
$isLocal = in_array($remoteAddress, ['127.0.0.1', '::1'], true);
if (!$isLocal) {
    http_response_code(403);
    exit('Diese Nostalgia-Verwaltung ist nur lokal erreichbar.');
}

$projectRoot = dirname(__DIR__, 3);
$serverDirectory = $projectRoot . DIRECTORY_SEPARATOR . 'Repack' . DIRECTORY_SEPARATOR . 'Server';
$loginConfig = $serverDirectory . DIRECTORY_SEPARATOR . 'realmd.conf';
$worldConfig = $serverDirectory . DIRECTORY_SEPARATOR . 'mangosd.conf';
$dumpDirectory = $serverDirectory;

if (empty($_SESSION['nostalgia_csrf'])) {
    $_SESSION['nostalgia_csrf'] = bin2hex(random_bytes(32));
}
$csrf = $_SESSION['nostalgia_csrf'];

$page = (string)($_REQUEST['page'] ?? 'home');
if (!in_array($page, ['home', 'accounts', 'characters'], true)) {
    $page = 'home';
}

function h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function requireCsrf(): void
{
    $posted = (string)($_POST['csrf'] ?? '');
    $stored = (string)($_SESSION['nostalgia_csrf'] ?? '');
    if ($posted === '' || $stored === '' || !hash_equals($stored, $posted)) {
        throw new RuntimeException('Die Anfrage ist abgelaufen. Bitte die Seite neu laden.');
    }
}

function databaseInfo(string $configFile, string $setting): array
{
    $content = @file_get_contents($configFile);
    $pattern = '/^' . preg_quote($setting, '/') . '\s*=\s*"([^"]+)"/mi';
    if ($content === false || !preg_match($pattern, $content, $match)) {
        throw new RuntimeException("Die Datenbank-Konfiguration {$setting} konnte nicht gelesen werden.");
    }

    $parts = explode(';', $match[1]);
    if (count($parts) !== 5) {
        throw new RuntimeException('Die Login-Datenbank-Konfiguration ist ungueltig.');
    }

    return $parts;
}

function databaseConnection(string $configFile, string $setting): PDO
{
    [$host, $port, $user, $password, $database] = databaseInfo($configFile, $setting);
    return new PDO(
        "mysql:host={$host};port={$port};dbname={$database};charset=utf8mb4",
        $user,
        $password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
}

function loginDatabase(string $configFile): PDO
{
    return databaseConnection($configFile, 'LoginDatabaseInfo');
}

function characterDatabase(string $configFile): PDO
{
    return databaseConnection($configFile, 'CharacterDatabaseInfo');
}

function gmpFromLittleEndian(string $bytes): GMP
{
    return gmp_init(bin2hex(strrev($bytes)), 16);
}

function vanillaSrp6(string $username, string $password): array
{
    if (!function_exists('gmp_powm')) {
        throw new RuntimeException('Die PHP-Erweiterung GMP ist nicht geladen.');
    }

    // AccountMgr::CalculateShaPassHash() im vMaNGOS-Core verwendet exakt
    // SHA1(UPPERCASE_USERNAME:UPPERCASE_PASSWORD).
    $passwordHash = sha1($username . ':' . $password, true);
    $salt = random_bytes(32);
    // Wie BN_rand(..., top = 0, bottom = 1): volle Salt-Laenge beibehalten.
    $salt[0] = chr(ord($salt[0]) | 0x80);

    // SRP6::CalculateVerifier() verarbeitet den Salt als Little-Endian-Array.
    $xDigest = sha1(strrev($salt) . $passwordHash, true);
    $x = gmpFromLittleEndian($xDigest);
    $prime = gmp_init('894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7', 16);
    $verifier = gmp_powm(gmp_init(7, 10), $x, $prime);

    return [
        strtoupper(gmp_strval($verifier, 16)),
        strtoupper(bin2hex($salt)),
    ];
}

function safeDumpName(string $filename): string
{
    $base = pathinfo(basename($filename), PATHINFO_FILENAME);
    $base = preg_replace('/[^A-Za-z0-9_-]/', '_', $base) ?? '';
    if ($base === '' || strlen($base) > 48) {
        throw new RuntimeException('Bitte einen Dateinamen mit 1 bis 48 Buchstaben, Zahlen, _ oder - verwenden.');
    }
    return $base . '.pdump';
}

function dumpFiles(string $directory): array
{
    $files = glob($directory . DIRECTORY_SEPARATOR . '*.pdump') ?: [];
    usort($files, static fn(string $a, string $b): int => filemtime($b) <=> filemtime($a));
    return $files;
}

$notice = '';
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        requireCsrf();
        $action = (string)($_POST['action'] ?? '');

        if ($action === 'create_account') {
            $username = strtoupper(trim((string)($_POST['username'] ?? '')));
            $password = strtoupper(trim((string)($_POST['password'] ?? '')));

            if (!preg_match('/^[A-Z0-9]{3,16}$/', $username)) {
                throw new RuntimeException('Der Accountname muss 3 bis 16 Zeichen lang sein und darf nur Buchstaben oder Zahlen enthalten.');
            }
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $password)) {
                throw new RuntimeException('Das Passwort muss 3 bis 16 Zeichen lang sein und darf nur Buchstaben oder Zahlen enthalten.');
            }

            [$verifier, $salt] = vanillaSrp6($username, $password);
            $database = loginDatabase($loginConfig);

            $exists = $database->prepare('SELECT 1 FROM account WHERE username = :username LIMIT 1');
            $exists->execute(['username' => $username]);
            if ($exists->fetchColumn()) {
                throw new RuntimeException('Dieser Accountname ist bereits vergeben.');
            }

            $insert = $database->prepare('INSERT INTO account (username, v, s, joindate) VALUES (:username, :verifier, :salt, NOW())');
            $insert->execute(['username' => $username, 'verifier' => $verifier, 'salt' => $salt]);
            $accountId = (int)$database->lastInsertId();

            $realmCharacters = $database->prepare('INSERT IGNORE INTO realmcharacters (realmid, acctid, numchars) SELECT id, :account, 0 FROM realmlist');
            $realmCharacters->execute(['account' => $accountId]);
            $notice = "Account {$username} wurde erstellt. Du kannst dich jetzt damit einloggen.";
        } elseif ($action === 'delete_account') {
            $username = strtoupper(trim((string)($_POST['username'] ?? '')));
            $confirmation = strtoupper(trim((string)($_POST['confirmation'] ?? '')));

            if (!preg_match('/^[A-Z0-9]{3,16}$/', $username)) {
                throw new RuntimeException('Bitte einen gueltigen Accountnamen eingeben.');
            }
            if ($confirmation !== 'LOESCHEN') {
                throw new RuntimeException('Zur Sicherheit muss LOESCHEN bestaetigt werden.');
            }

            $loginDatabase = loginDatabase($loginConfig);
            $findAccount = $loginDatabase->prepare('SELECT id FROM account WHERE username = :username LIMIT 1');
            $findAccount->execute(['username' => $username]);
            $accountId = $findAccount->fetchColumn();
            if ($accountId === false) {
                throw new RuntimeException('Dieser Account wurde nicht gefunden.');
            }

            $characterDatabase = characterDatabase($worldConfig);
            $characterCount = $characterDatabase->prepare('SELECT COUNT(*) FROM characters WHERE account = :account');
            $characterCount->execute(['account' => (int)$accountId]);
            $characters = (int)$characterCount->fetchColumn();
            if ($characters > 0) {
                throw new RuntimeException("{$username} besitzt noch {$characters} Charakter(e). Zum Schutz der Charakterdaten ist das Loeschen hier gesperrt.");
            }

            $loginDatabase->beginTransaction();
            try {
                $loginDatabase->prepare('DELETE FROM realmcharacters WHERE acctid = :account')->execute(['account' => (int)$accountId]);
                $loginDatabase->prepare('DELETE FROM account WHERE id = :account')->execute(['account' => (int)$accountId]);
                $loginDatabase->commit();
            } catch (Throwable $exception) {
                if ($loginDatabase->inTransaction()) {
                    $loginDatabase->rollBack();
                }
                throw $exception;
            }

            $notice = "Account {$username} wurde geloescht.";
        } elseif ($action === 'upload_dump') {
            if (!isset($_FILES['pdump']) || !is_array($_FILES['pdump'])) {
                throw new RuntimeException('Bitte eine .pdump-Datei auswaehlen.');
            }
            $upload = $_FILES['pdump'];
            if ((int)$upload['error'] !== UPLOAD_ERR_OK) {
                throw new RuntimeException('Der Upload ist fehlgeschlagen.');
            }
            if ((int)$upload['size'] < 1 || (int)$upload['size'] > 10 * 1024 * 1024) {
                throw new RuntimeException('Die .pdump-Datei darf hoechstens 10 MB gross sein.');
            }
            if (!is_uploaded_file((string)$upload['tmp_name'])) {
                throw new RuntimeException('Die Upload-Datei ist ungueltig.');
            }

            $targetName = safeDumpName((string)$upload['name']);
            $header = (string)file_get_contents((string)$upload['tmp_name'], false, null, 0, 512);
            if (strpos($header, 'IMPORTANT NOTE:') === false) {
                throw new RuntimeException('Das ist keine gueltige vMaNGOS-.pdump-Datei.');
            }

            $target = $dumpDirectory . DIRECTORY_SEPARATOR . $targetName;
            if (file_exists($target)) {
                throw new RuntimeException("Die Sicherung {$targetName} existiert bereits. Bitte die Datei vorher umbenennen.");
            }
            if (!move_uploaded_file((string)$upload['tmp_name'], $target)) {
                throw new RuntimeException('Die Sicherung konnte nicht in den Serverordner verschoben werden.');
            }
            $notice = "{$targetName} wurde hochgeladen. Im Spiel jetzt .x load " . pathinfo($targetName, PATHINFO_FILENAME) . " verwenden.";
        } elseif ($action === 'download_dump') {
            $filename = safeDumpName((string)($_POST['filename'] ?? ''));
            $path = $dumpDirectory . DIRECTORY_SEPARATOR . $filename;
            if (!is_file($path)) {
                throw new RuntimeException('Die angeforderte Sicherung wurde nicht gefunden.');
            }

            header('Content-Type: text/plain; charset=utf-8');
            header('Content-Length: ' . (string)filesize($path));
            header('Content-Disposition: attachment; filename="' . $filename . '"');
            readfile($path);
            exit;
        }
    } catch (Throwable $exception) {
        error_log('Nostalgia-Verwaltung: ' . $exception->getMessage());
        $error = $exception instanceof PDOException
            ? 'Die Datenbankverbindung ist momentan nicht verfuegbar. Starte zuerst den Server oder MariaDB.'
            : $exception->getMessage();
    }
}

$dumps = is_dir($dumpDirectory) ? dumpFiles($dumpDirectory) : [];
?>
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Nostalgia Verwaltung</title>
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
    <style type="text/tailwindcss">
        @theme {
            --color-ink: #07101e;
            --color-night: #0b1729;
            --color-panel: #101f37;
            --color-gold: #f2c55c;
            --color-sky: #9fd0ff;
            --shadow-glow: 0 0 0 1px rgba(242,197,92,.22), 0 24px 60px rgba(0,0,0,.42);
        }

        body { background: #07101e; }
    </style>
</head>
<body class="min-h-screen overflow-x-hidden bg-ink font-serif text-slate-100 selection:bg-gold/30 selection:text-white">
<div class="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
    <div class="absolute -top-52 left-1/2 h-[34rem] w-[54rem] -translate-x-1/2 rounded-full bg-sky/15 blur-3xl"></div>
    <div class="absolute -bottom-64 -left-40 h-[38rem] w-[38rem] rounded-full bg-amber-600/10 blur-3xl"></div>
</div>
<main class="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 lg:py-12">
    <header class="mb-8 text-center sm:mb-12">
        <img class="mx-auto mb-1 w-72 max-w-[85vw] drop-shadow-[0_8px_16px_rgba(0,0,0,.8)] sm:w-96" src="assets/nostalgia-logo.png" alt="Nostalgia">
        <div class="mx-auto flex max-w-xl items-center gap-3 before:h-px before:flex-1 before:bg-gradient-to-r before:from-transparent before:to-gold/70 after:h-px after:flex-1 after:bg-gradient-to-l after:from-transparent after:to-gold/70">
            <span class="text-[10px] tracking-[.42em] text-gold/90">VANILLA REIMAGINED</span>
        </div>
        <h1 class="mt-3 text-4xl font-bold tracking-[.16em] text-gold [text-shadow:0_3px_0_#35200b,0_8px_24px_rgba(0,0,0,.7)] sm:text-5xl">NOSTALGIA</h1>
        <p class="mt-3 text-sm tracking-wide text-sky sm:text-base">Lokale Account- und Charakterverwaltung</p>
        <nav class="mt-7 flex flex-wrap justify-center gap-2" aria-label="Hauptnavigation">
            <a class="rounded-xl border px-4 py-2 text-sm font-bold transition <?= $page === 'home' ? 'border-gold bg-amber-500/20 text-amber-100 shadow-glow' : 'border-slate-500/50 bg-slate-950/40 text-slate-200 hover:border-gold/70 hover:bg-slate-800/70 hover:text-gold' ?>" href="?page=home">Startseite</a>
            <a class="rounded-xl border px-4 py-2 text-sm font-bold transition <?= $page === 'accounts' ? 'border-gold bg-amber-500/20 text-amber-100 shadow-glow' : 'border-slate-500/50 bg-slate-950/40 text-slate-200 hover:border-gold/70 hover:bg-slate-800/70 hover:text-gold' ?>" href="?page=accounts">Account verwalten</a>
            <a class="rounded-xl border px-4 py-2 text-sm font-bold transition <?= $page === 'characters' ? 'border-gold bg-amber-500/20 text-amber-100 shadow-glow' : 'border-slate-500/50 bg-slate-950/40 text-slate-200 hover:border-gold/70 hover:bg-slate-800/70 hover:text-gold' ?>" href="?page=characters">Charaktere</a>
        </nav>
    </header>

    <?php if ($notice !== ''): ?><div class="mb-6 rounded-xl border border-emerald-400/50 bg-emerald-950/70 px-5 py-4 text-emerald-200 shadow-lg" role="status"><?= h($notice) ?></div><?php endif; ?>
    <?php if ($error !== ''): ?><div class="mb-6 rounded-xl border border-red-400/50 bg-red-950/70 px-5 py-4 text-red-200 shadow-lg" role="alert"><?= h($error) ?></div><?php endif; ?>

    <?php if ($page === 'home'): ?>
    <section class="grid gap-5 md:grid-cols-2">
        <article class="group relative overflow-hidden rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 p-6 shadow-xl transition duration-300 hover:-translate-y-1 hover:border-gold/60 hover:shadow-glow">
            <div class="mb-5 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-gold/40 bg-amber-400/10 text-xl text-gold">✦</div>
            <h2 class="mb-3 text-xl font-bold text-gold">Vanilla, wie es sich erinnern soll</h2>
            <p class="leading-7 text-slate-300">Naxxramas ist das Endziel. Molten Core und Blackwing Lair sind verfuegbar, Zul'Gurub und Ahn'Qiraj bleiben geschlossen.</p>
        </article>
        <article class="group relative overflow-hidden rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 p-6 shadow-xl transition duration-300 hover:-translate-y-1 hover:border-gold/60 hover:shadow-glow">
            <div class="mb-5 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-sky/40 bg-sky/10 text-xl text-sky">◌</div>
            <h2 class="mb-3 text-xl font-bold text-gold">Eine lebendige Welt</h2>
            <p class="leading-7 text-slate-300">Der globale Allgemein-Chat, fiktive Spieler, Gilden und Gruppenaufrufe geben der Welt wieder echtes Vanilla-Gefuehl.</p>
        </article>
        <article class="group relative overflow-hidden rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 p-6 shadow-xl transition duration-300 hover:-translate-y-1 hover:border-gold/60 hover:shadow-glow">
            <div class="mb-5 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-violet-300/40 bg-violet-400/10 text-xl text-violet-200">⚔</div>
            <h2 class="mb-3 text-xl font-bold text-gold">Gemeinsam oder solo</h2>
            <p class="leading-7 text-slate-300">PartyBots, gemeinsames Auktionshaus und der Transmogger machen kleine Runden angenehm spielbar.</p>
        </article>
        <article class="relative overflow-hidden rounded-2xl border border-gold/40 bg-gradient-to-br from-amber-950/55 to-slate-950/95 p-6 shadow-xl">
            <div class="mb-5 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-gold/40 bg-amber-400/10 text-xl text-gold">⌘</div>
            <h2 class="mb-3 text-xl font-bold text-gold">Lokale Verwaltung</h2>
            <p class="mb-5 leading-7 text-slate-300">Konten anlegen oder loeschen sowie Charakter-Sicherungen hoch- und herunterladen.</p>
            <div class="flex flex-wrap gap-3">
                <a class="rounded-lg border border-gold/70 bg-amber-500/15 px-4 py-2 text-sm font-bold text-amber-100 transition hover:bg-amber-400/25" href="?page=accounts">Accounts</a>
                <a class="rounded-lg border border-sky/50 bg-sky/10 px-4 py-2 text-sm font-bold text-sky transition hover:bg-sky/20" href="?page=characters">Charaktere</a>
            </div>
        </article>
    </section>
    <?php elseif ($page === 'accounts'): ?>
    <section class="grid gap-5 lg:grid-cols-2">
        <article class="rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 p-6 shadow-xl sm:p-8">
            <div class="mb-5 flex items-start gap-4"><span class="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-emerald-300/40 bg-emerald-400/10 text-xl text-emerald-200">+</span><div><h2 class="text-xl font-bold text-gold">Account erstellen</h2><p class="mt-1 text-sm leading-6 text-slate-400">Normales Spieler-Konto mit dem gleichen SRP6-Verfahren wie die Worldserver-Konsole.</p></div></div>
            <form class="space-y-4" method="post" autocomplete="off">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="action" value="create_account">
                <input type="hidden" name="page" value="accounts">
                <div><label class="mb-2 block text-sm font-bold text-sky" for="username">Accountname</label><input class="block w-full rounded-xl border border-slate-500/60 bg-slate-950/70 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-gold focus:ring-2 focus:ring-gold/20" id="username" name="username" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required></div>
                <div><label class="mb-2 block text-sm font-bold text-sky" for="password">Passwort</label><input class="block w-full rounded-xl border border-slate-500/60 bg-slate-950/70 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-gold focus:ring-2 focus:ring-gold/20" id="password" name="password" type="password" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required></div>
                <button class="w-full rounded-xl border border-gold/80 bg-gradient-to-b from-amber-400/30 to-amber-700/25 px-5 py-3 font-bold text-amber-50 shadow-lg transition hover:brightness-125 focus:outline-none focus:ring-2 focus:ring-gold/50" type="submit">Account anlegen</button>
            </form>
        </article>

        <article class="rounded-2xl border border-red-400/35 bg-gradient-to-br from-red-950/55 to-slate-950/90 p-6 shadow-xl sm:p-8">
            <div class="mb-5 flex items-start gap-4"><span class="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-red-300/40 bg-red-400/10 text-xl text-red-200">!</span><div><h2 class="text-xl font-bold text-gold">Account loeschen</h2><p class="mt-1 text-sm leading-6 text-slate-400">Nur Konten ohne Charaktere koennen hier geloescht werden. So bleiben Charakterdaten geschuetzt.</p></div></div>
            <form class="space-y-4" method="post" autocomplete="off" onsubmit="return confirm('Diesen leeren Account wirklich unwiderruflich loeschen?');">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="action" value="delete_account">
                <input type="hidden" name="page" value="accounts">
                <div><label class="mb-2 block text-sm font-bold text-sky" for="delete_username">Accountname</label><input class="block w-full rounded-xl border border-red-300/30 bg-slate-950/70 px-4 py-3 text-white outline-none transition focus:border-red-300 focus:ring-2 focus:ring-red-300/20" id="delete_username" name="username" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required></div>
                <div><label class="mb-2 block text-sm font-bold text-sky" for="confirmation">Zur Bestaetigung <span class="text-red-200">LOESCHEN</span> eingeben</label><input class="block w-full rounded-xl border border-red-300/30 bg-slate-950/70 px-4 py-3 text-white outline-none transition focus:border-red-300 focus:ring-2 focus:ring-red-300/20" id="confirmation" name="confirmation" maxlength="8" pattern="LOESCHEN" required></div>
                <button class="w-full rounded-xl border border-red-300/70 bg-gradient-to-b from-red-500/35 to-red-900/45 px-5 py-3 font-bold text-red-50 shadow-lg transition hover:brightness-125 focus:outline-none focus:ring-2 focus:ring-red-300/50" type="submit">Leeren Account loeschen</button>
            </form>
        </article>
    </section>
    <?php else: ?>
    <section class="grid gap-5">

        <article class="rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 p-6 shadow-xl sm:p-8">
            <div class="grid items-center gap-8 lg:grid-cols-[1fr_280px]">
                <div>
                    <div class="mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-gold/40 bg-amber-400/10 text-xl text-gold">▣</div>
                    <h2 class="mb-3 text-2xl font-bold text-gold">Charakter sichern</h2>
                    <p class="mb-5 leading-7 text-slate-300">Eine Sicherung wird bewusst vom Worldserver erstellt, damit auch Inventar, Zauber, Quests und Begleiter korrekt enthalten sind.</p>
                    <ol class="space-y-3 text-slate-300">
                        <li class="flex gap-3"><span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-sky/15 text-xs font-bold text-sky">1</span><span>Mit dem gewuenschten Charakter einloggen.</span></li>
                        <li class="flex gap-3"><span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-sky/15 text-xs font-bold text-sky">2</span><span>Im Chat <code class="rounded bg-slate-950 px-2 py-1 text-sm text-amber-100">.x save meinchar</code> eingeben.</span></li>
                        <li class="flex gap-3"><span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-sky/15 text-xs font-bold text-sky">3</span><span>Die Datei <code class="rounded bg-slate-950 px-2 py-1 text-sm text-amber-100">meinchar.pdump</code> erscheint unten und kann heruntergeladen werden.</span></li>
                    </ol>
                </div>
                <img class="mx-auto w-full max-w-[280px] rounded-2xl border border-gold/40 shadow-glow" src="assets/character-backup.png" alt="Abenteurer-Tasche, Charakterakte und magische Sicherungsrune">
            </div>
        </article>

        <article class="rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 p-6 shadow-xl sm:p-8">
            <h2 class="mb-2 text-2xl font-bold text-gold">Charakter-Sicherung hochladen</h2>
            <p class="mb-6 max-w-3xl leading-7 text-slate-400">Nur vMaNGOS-<code class="rounded bg-slate-950 px-2 py-1 text-sm text-amber-100">.pdump</code>-Dateien verwenden. Nach dem Upload mit einem Charakter des Zielkontos einloggen und <code class="rounded bg-slate-950 px-2 py-1 text-sm text-amber-100">.x load dateiname</code> ohne die Endung eingeben.</p>
            <form class="flex flex-col gap-4 sm:flex-row sm:items-end" method="post" enctype="multipart/form-data">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="action" value="upload_dump">
                <input type="hidden" name="page" value="characters">
                <div class="w-full"><label class="mb-2 block text-sm font-bold text-sky" for="pdump">.pdump-Datei (maximal 10 MB)</label><input class="block w-full cursor-pointer rounded-xl border border-dashed border-sky/40 bg-slate-950/55 px-3 py-3 text-sm text-slate-300 file:mr-4 file:rounded-lg file:border-0 file:bg-sky/15 file:px-3 file:py-2 file:font-bold file:text-sky hover:file:bg-sky/25" id="pdump" name="pdump" type="file" accept=".pdump,text/plain" required></div>
                <button class="shrink-0 rounded-xl border border-gold/80 bg-gradient-to-b from-amber-400/30 to-amber-700/25 px-5 py-3 font-bold text-amber-50 shadow-lg transition hover:brightness-125 focus:outline-none focus:ring-2 focus:ring-gold/50" type="submit">Hochladen</button>
            </form>
        </article>

        <article class="overflow-hidden rounded-2xl border border-slate-500/40 bg-gradient-to-br from-panel/95 to-slate-950/90 shadow-xl">
            <div class="border-b border-slate-500/30 px-6 py-5 sm:px-8"><h2 class="text-2xl font-bold text-gold">Vorhandene Sicherungen</h2></div>
            <?php if ($dumps === []): ?>
                <p class="px-6 py-7 text-slate-400 sm:px-8">Noch keine .pdump-Dateien vorhanden. Erstelle die erste Sicherung mit <code class="rounded bg-slate-950 px-2 py-1 text-sm text-amber-100">.x save dateiname</code>.</p>
            <?php else: ?>
                <div class="overflow-x-auto"><table class="w-full min-w-[620px] text-left text-sm">
                    <thead class="bg-slate-950/45 text-xs uppercase tracking-wider text-sky"><tr><th class="px-6 py-4 font-bold sm:px-8">Datei</th><th class="px-4 py-4 font-bold">Groesse</th><th class="px-4 py-4 font-bold">Geaendert</th><th class="px-6 py-4 sm:px-8"></th></tr></thead>
                    <tbody>
                    <?php foreach ($dumps as $dump): $name = basename($dump); ?>
                        <tr class="border-t border-slate-600/30 text-slate-300 transition hover:bg-slate-800/45">
                            <td class="px-6 py-4 font-bold text-slate-100 sm:px-8"><?= h($name) ?></td>
                            <td class="px-4 py-4"><?= h(number_format((int)filesize($dump) / 1024, 1, ',', '.')) ?> KB</td>
                            <td class="px-4 py-4 text-slate-400"><?= h(date('d.m.Y H:i', (int)filemtime($dump))) ?></td>
                            <td class="px-6 py-4 text-right sm:px-8"><form method="post"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="download_dump"><input type="hidden" name="page" value="characters"><input type="hidden" name="filename" value="<?= h($name) ?>"><button class="rounded-lg border border-sky/45 bg-sky/10 px-3 py-2 text-xs font-bold text-sky transition hover:bg-sky/20" type="submit">Download</button></form></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
            <?php endif; ?>
        </article>
    </section>
    <?php endif; ?>

    <footer class="mt-8 border-t border-slate-500/25 pt-6 text-center text-sm tracking-wide text-slate-500">Nostalgia by Xarinia 2026</footer>
</main>
</body>
</html>
