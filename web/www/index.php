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
    <style>
        :root { color-scheme: dark; --gold: #d8ad43; --blue: #9ecbff; --ink: #09101f; --panel: #101b31; --line: #546d95; --green: #81d49a; --red: #ff9898; }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; color: #e6edf9; background: radial-gradient(circle at top, #20385b 0, #09101f 48rem); font: 16px/1.5 Georgia, "Times New Roman", serif; }
        main { width: min(980px, calc(100% - 32px)); margin: 32px auto 44px; }
        header { text-align: center; margin-bottom: 28px; }
        .logo { display: block; width: min(360px, 84vw); height: auto; margin: 0 auto 2px; filter: drop-shadow(0 4px 9px rgba(0,0,0,.75)); }
        h1 { margin: 0; color: var(--gold); letter-spacing: .08em; font-size: clamp(2rem, 5vw, 3.2rem); text-shadow: 0 2px #000; }
        header p { margin: 6px 0 0; color: var(--blue); }
        nav { display: flex; justify-content: center; flex-wrap: wrap; gap: 8px; margin-top: 20px; }
        nav a { border: 1px solid #617ca6; border-radius: 4px; padding: 7px 13px; color: #dceaff; background: rgba(6, 12, 24, .7); font-weight: bold; text-decoration: none; }
        nav a:hover, nav a.active { border-color: #efc95d; color: #fff3bb; background: rgba(96, 42, 24, .8); }
        .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 20px; }
        .card { border: 1px solid var(--line); border-radius: 8px; padding: 22px; background: linear-gradient(145deg, rgba(28, 48, 82, .94), rgba(10, 18, 33, .94)); box-shadow: 0 12px 30px rgba(0,0,0,.28); }
        .wide { grid-column: 1 / -1; }
        h2 { margin: 0 0 14px; color: var(--gold); font-size: 1.35rem; }
        p { margin: 0 0 14px; }
        label { display: block; margin: 12px 0 5px; color: var(--blue); font-weight: bold; }
        input { width: 100%; border: 1px solid #6682ad; border-radius: 4px; padding: 10px; color: #fff; background: #060c18; font: inherit; }
        button { margin-top: 16px; border: 1px solid #efc95d; border-radius: 4px; padding: 10px 16px; color: #fff3bb; background: linear-gradient(#7d2727, #411011); font: bold 16px Georgia, serif; cursor: pointer; }
        button:hover { filter: brightness(1.2); }
        .notice, .error { margin-bottom: 20px; border-radius: 5px; padding: 12px 16px; }
        .notice { border: 1px solid #4c9b65; color: var(--green); background: rgba(24, 78, 42, .65); }
        .error { border: 1px solid #ab4545; color: var(--red); background: rgba(96, 25, 25, .65); }
        code { padding: 2px 5px; border-radius: 3px; color: #fff0ae; background: #060c18; }
        .steps { margin: 0; padding-left: 22px; }
        .steps li { margin: 8px 0; }
        table { width: 100%; border-collapse: collapse; font-size: .95rem; }
        th, td { padding: 10px 6px; border-bottom: 1px solid rgba(137, 165, 207, .25); text-align: left; }
        th { color: var(--blue); }
        .download { margin: 0; }
        .download button { margin: 0; padding: 6px 10px; font-size: .9rem; }
        .danger { border-color: #9c4545; background: linear-gradient(145deg, rgba(74, 25, 31, .94), rgba(29, 9, 13, .94)); }
        .danger button { border-color: #ed7777; background: linear-gradient(#8b1d28, #44080d); }
        .feature { min-height: 150px; }
        .feature h2 { font-size: 1.18rem; }
        .action-link { display: inline-block; margin-top: 4px; border: 1px solid #efc95d; border-radius: 4px; padding: 9px 14px; color: #fff3bb; background: linear-gradient(#7d2727, #411011); font-weight: bold; text-decoration: none; }
        .backup-layout { display: grid; grid-template-columns: minmax(0, 1fr) minmax(210px, 290px); align-items: center; gap: 22px; }
        .backup-art { display: block; width: 100%; max-width: 290px; margin: 0 auto; border: 1px solid rgba(216, 173, 67, .45); border-radius: 6px; box-shadow: 0 8px 22px rgba(0, 0, 0, .42); }
        .muted { color: #b4c1d7; font-size: .92rem; }
        footer { margin-top: 20px; color: #99a9c3; text-align: center; font-size: .9rem; }
        @media (max-width: 700px) { main { margin: 24px auto; } .grid { grid-template-columns: 1fr; } .wide { grid-column: auto; } .backup-layout { grid-template-columns: 1fr; } .backup-art { max-width: 250px; } }
    </style>
</head>
<body>
<main>
    <header>
        <img class="logo" src="assets/nostalgia-logo.png" alt="Nostalgia">
        <h1>NOSTALGIA</h1>
        <p>Lokale Account- und Charakterverwaltung</p>
        <nav aria-label="Hauptnavigation">
            <a class="<?= $page === 'home' ? 'active' : '' ?>" href="?page=home">Startseite</a>
            <a class="<?= $page === 'accounts' ? 'active' : '' ?>" href="?page=accounts">Account verwalten</a>
            <a class="<?= $page === 'characters' ? 'active' : '' ?>" href="?page=characters">Charaktere</a>
        </nav>
    </header>

    <?php if ($notice !== ''): ?><div class="notice"><?= h($notice) ?></div><?php endif; ?>
    <?php if ($error !== ''): ?><div class="error"><?= h($error) ?></div><?php endif; ?>

    <?php if ($page === 'home'): ?>
    <section class="grid">
        <article class="card feature">
            <h2>Vanilla, wie es sich erinnern soll</h2>
            <p>Naxxramas ist das Endziel. Molten Core und Blackwing Lair sind verfuegbar, Zul'Gurub und Ahn'Qiraj bleiben geschlossen.</p>
        </article>
        <article class="card feature">
            <h2>Eine lebendige Welt</h2>
            <p>Der globale Allgemein-Chat, fiktive Spieler, Gilden und Gruppenaufrufe geben der Welt wieder echtes Vanilla-Gefuehl.</p>
        </article>
        <article class="card feature">
            <h2>Gemeinsam oder solo</h2>
            <p>PartyBots, gemeinsames Auktionshaus und der Transmogger machen kleine Runden angenehm spielbar.</p>
        </article>
        <article class="card feature">
            <h2>Lokale Verwaltung</h2>
            <p>Konten anlegen oder loeschen sowie Charakter-Sicherungen hoch- und herunterladen.</p>
            <a class="action-link" href="?page=accounts">Account verwalten</a>
            <a class="action-link" href="?page=characters">Charaktere</a>
        </article>
    </section>
    <?php elseif ($page === 'accounts'): ?>
    <section class="grid">
        <article class="card">
            <h2>Account erstellen</h2>
            <p class="muted">Erstellt ein normales Spieler-Konto mit dem gleichen SRP6-Verfahren wie die Worldserver-Konsole.</p>
            <form method="post" autocomplete="off">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="action" value="create_account">
                <input type="hidden" name="page" value="accounts">
                <label for="username">Accountname</label>
                <input id="username" name="username" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required>
                <label for="password">Passwort</label>
                <input id="password" name="password" type="password" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required>
                <button type="submit">Account anlegen</button>
            </form>
        </article>

        <article class="card danger">
            <h2>Account loeschen</h2>
            <p class="muted">Nur Konten ohne Charaktere koennen hier geloescht werden. Das verhindert, dass Charakterdaten versehentlich verloren gehen.</p>
            <form method="post" autocomplete="off" onsubmit="return confirm('Diesen leeren Account wirklich unwiderruflich loeschen?');">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="action" value="delete_account">
                <input type="hidden" name="page" value="accounts">
                <label for="delete_username">Accountname</label>
                <input id="delete_username" name="username" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required>
                <label for="confirmation">Zur Bestaetigung LOESCHEN eingeben</label>
                <input id="confirmation" name="confirmation" maxlength="8" pattern="LOESCHEN" required>
                <button type="submit">Account loeschen</button>
            </form>
        </article>
    </section>
    <?php else: ?>
    <section class="grid">

        <article class="card wide">
            <div class="backup-layout">
                <div>
                    <h2>Charakter sichern</h2>
                    <p class="muted">Eine Sicherung wird bewusst vom Worldserver erstellt, damit auch Inventar, Zauber, Quests und Begleiter korrekt enthalten sind.</p>
                    <ol class="steps">
                        <li>Mit dem gewuenschten Charakter einloggen.</li>
                        <li>Im Chat <code>.x save meinchar</code> eingeben.</li>
                        <li>Die Datei <code>meinchar.pdump</code> erscheint unten und kann heruntergeladen werden.</li>
                    </ol>
                </div>
                <img class="backup-art" src="assets/character-backup.png" alt="Abenteurer-Tasche, Charakterakte und magische Sicherungsrune">
            </div>
        </article>

        <article class="card wide">
            <h2>Charakter-Sicherung hochladen</h2>
            <p class="muted">Nur vMaNGOS-<code>.pdump</code>-Dateien verwenden. Nach dem Upload mit einem Charakter des Zielkontos einloggen und <code>.x load dateiname</code> ohne die Endung eingeben. Der Import erstellt einen Charakter auf diesem Konto.</p>
            <form method="post" enctype="multipart/form-data">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="action" value="upload_dump">
                <input type="hidden" name="page" value="characters">
                <label for="pdump">.pdump-Datei (maximal 10 MB)</label>
                <input id="pdump" name="pdump" type="file" accept=".pdump,text/plain" required>
                <button type="submit">Sicherung hochladen</button>
            </form>
        </article>

        <article class="card wide">
            <h2>Vorhandene Sicherungen</h2>
            <?php if ($dumps === []): ?>
                <p class="muted">Noch keine .pdump-Dateien vorhanden. Erstelle die erste Sicherung mit <code>.x save dateiname</code>.</p>
            <?php else: ?>
                <table>
                    <thead><tr><th>Datei</th><th>Groesse</th><th>Geaendert</th><th></th></tr></thead>
                    <tbody>
                    <?php foreach ($dumps as $dump): $name = basename($dump); ?>
                        <tr>
                            <td><?= h($name) ?></td>
                            <td><?= h(number_format((int)filesize($dump) / 1024, 1, ',', '.')) ?> KB</td>
                            <td><?= h(date('d.m.Y H:i', (int)filemtime($dump))) ?></td>
                            <td><form class="download" method="post"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="download_dump"><input type="hidden" name="page" value="characters"><input type="hidden" name="filename" value="<?= h($name) ?>"><button type="submit">Download</button></form></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </article>
    </section>
    <?php endif; ?>

    <footer>Nostalgia by Xarinia 2026</footer>
</main>
</body>
</html>
