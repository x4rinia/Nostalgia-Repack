<?php declare(strict_types=1);

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
    exit('The web session folder could not be created.');
}
ini_set('session.save_path', $sessionDirectory);
session_start();

$remoteAddress = $_SERVER['REMOTE_ADDR'] ?? '';
$isLocal = in_array($remoteAddress, ['127.0.0.1', '::1'], true);
if (!$isLocal) {
    http_response_code(403);
    exit('This Nostalgia administration site is available only from the local machine.');
}

$serverDirectory = dirname(__DIR__, 2) . DIRECTORY_SEPARATOR . 'Server';
$loginConfig = $serverDirectory . DIRECTORY_SEPARATOR . 'realmd.conf';
$worldConfig = $serverDirectory . DIRECTORY_SEPARATOR . 'mangosd.conf';
$dumpDirectory = dirname(__DIR__, 2) . DIRECTORY_SEPARATOR . 'backups' . DIRECTORY_SEPARATOR . 'characters';
if (!is_dir($dumpDirectory)) {
    @mkdir($dumpDirectory, 0777, true);
}

if (empty($_SESSION['nostalgia_csrf'])) {
    $_SESSION['nostalgia_csrf'] = bin2hex(random_bytes(32));
}
$csrf = $_SESSION['nostalgia_csrf'];

$page = (string)($_REQUEST['page'] ?? 'home');
if (!in_array($page, ['home', 'accounts', 'characters', 'attunements'], true)) {
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
        throw new RuntimeException('The request expired. Reload the page.');
    }
}

function databaseInfo(string $configFile, string $setting): array
{
    $content = @file_get_contents($configFile);
    $pattern = '/^' . preg_quote($setting, '/') . '\s*=\s*"([^"]+)"/mi';
    if ($content === false || !preg_match($pattern, $content, $match)) {
        throw new RuntimeException("Database configuration {$setting} could not be read.");
    }

    $parts = explode(';', $match[1]);
    if (count($parts) !== 5) {
        throw new RuntimeException('The login database configuration is invalid.');
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
    return databaseConnection($configFile, 'CharacterDatabase.Info');
}

function gmpFromLittleEndian(string $bytes): GMP
{
    return gmp_init(bin2hex(strrev($bytes)), 16);
}

function vanillaSrp6(string $username, string $password): array
{
    if (!function_exists('gmp_powm')) {
        throw new RuntimeException('The PHP GMP extension is not loaded.');
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
        throw new RuntimeException('Use a filename containing 1 to 48 letters, digits, underscores or hyphens.');
    }
    return $base . '.pdump';
}

function dumpFiles(string $directory): array
{
    $files = glob($directory . DIRECTORY_SEPARATOR . '*.pdump') ?: [];
    usort($files, static fn(string $a, string $b): int => filemtime($b) <=> filemtime($a));
    return $files;
}

function isWorldServerRunning(): bool
{
    exec('tasklist /FI "IMAGENAME eq mangosd.exe" /NH 2>NUL', $output);
    foreach ($output as $line) {
        if (stripos($line, 'mangosd.exe') !== false) {
            return true;
        }
    }
    return false;
}

function sendWorldServerCommand(string $command): bool
{
    $pipe = @fopen('\\\\.\\pipe\\nostalgia_console', 'w');
    if ($pipe !== false) {
        fwrite($pipe, $command . "\n");
        fclose($pipe);
        return true;
    }
    return false;
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
                throw new RuntimeException('The account name must contain 3 to 16 letters or digits.');
            }
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $password)) {
                throw new RuntimeException('The password must contain 3 to 16 letters or digits.');
            }

            [$verifier, $salt] = vanillaSrp6($username, $password);
            $database = loginDatabase($loginConfig);

            $exists = $database->prepare('SELECT 1 FROM account WHERE username = :username LIMIT 1');
            $exists->execute(['username' => $username]);
            if ($exists->fetchColumn()) {
                throw new RuntimeException('This account name is already in use.');
            }

            $insert = $database->prepare('INSERT INTO account (username, v, s, joindate) VALUES (:username, :verifier, :salt, NOW())');
            $insert->execute(['username' => $username, 'verifier' => $verifier, 'salt' => $salt]);
            $accountId = (int)$database->lastInsertId();

            $realmCharacters = $database->prepare('INSERT IGNORE INTO realmcharacters (realmid, acctid, numchars) SELECT id, :account, 0 FROM realmlist');
            $realmCharacters->execute(['account' => $accountId]);
            $notice = "Account {$username} was created. You can now sign in with it.";
        } elseif ($action === 'delete_account') {
            $username = strtoupper(trim((string)($_POST['username'] ?? '')));
            $confirmation = strtoupper(trim((string)($_POST['confirmation'] ?? '')));

            if ($username === '' || !preg_match('/^[A-Z0-9]{3,16}$/', $username)) {
                throw new RuntimeException('Enter a valid account name.');
            }
            if ($username === 'ADMIN' || $username === 'AHBOT') {
                throw new RuntimeException('This system account is protected and cannot be deleted.');
            }
            if ($confirmation !== $username) {
                throw new RuntimeException("For confirmation, enter exactly {$username}.");
            }

            $loginDatabase = loginDatabase($loginConfig);
            $findAccount = $loginDatabase->prepare('SELECT id FROM account WHERE username = :username LIMIT 1');
            $findAccount->execute(['username' => $username]);
            $accountId = $findAccount->fetchColumn();
            if ($accountId === false) {
                throw new RuntimeException('This account was not found.');
            }

            $characterDatabase = characterDatabase($worldConfig);
            $characterCount = $characterDatabase->prepare('SELECT COUNT(*) FROM characters WHERE account = :account');
            $characterCount->execute(['account' => (int)$accountId]);
            $characters = (int)$characterCount->fetchColumn();
            if ($characters > 0) {
                throw new RuntimeException("{$username} still owns {$characters} character(s). Delete those characters before deleting the account.");
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

            $notice = "Account {$username} was deleted.";
        } elseif ($action === 'upload_dump') {
            $accountName = strtoupper(trim((string)($_POST['account_name'] ?? '')));
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $accountName)) throw new RuntimeException('Invalid account name.');
            $accountDir = $dumpDirectory . DIRECTORY_SEPARATOR . $accountName;
            if (!is_dir($accountDir)) @mkdir($accountDir, 0777, true);

            if (!isset($_FILES['pdump']) || !is_array($_FILES['pdump'])) throw new RuntimeException('Select a .pdump file.');
            $upload = $_FILES['pdump'];
            if ((int)$upload['error'] !== UPLOAD_ERR_OK) throw new RuntimeException('The upload failed.');
            if ((int)$upload['size'] < 1 || (int)$upload['size'] > 10 * 1024 * 1024) throw new RuntimeException('The .pdump file must not exceed 10 MB.');
            if (!is_uploaded_file((string)$upload['tmp_name'])) throw new RuntimeException('The uploaded file is invalid.');

            $targetName = safeDumpName((string)$upload['name']);
            $header = (string)file_get_contents((string)$upload['tmp_name'], false, null, 0, 512);
            if (strpos($header, 'IMPORTANT NOTE:') === false) throw new RuntimeException('This is not a valid vMaNGOS .pdump file.');

            $target = $accountDir . DIRECTORY_SEPARATOR . $targetName;
            if (file_exists($target)) throw new RuntimeException("Backup {$targetName} already exists.");
            if (!move_uploaded_file((string)$upload['tmp_name'], $target)) throw new RuntimeException('Could not save the file.');
            $notice = "Backup {$targetName} was uploaded.";
        } elseif ($action === 'download_dump') {
            $accountName = strtoupper(trim((string)($_POST['account_name'] ?? '')));
            $filename = safeDumpName((string)($_POST['filename'] ?? ''));
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $accountName)) throw new RuntimeException('Invalid account name.');
            
            $path = $dumpDirectory . DIRECTORY_SEPARATOR . $accountName . DIRECTORY_SEPARATOR . $filename;
            if (!is_file($path)) throw new RuntimeException('The backup was not found.');

            header('Content-Type: application/octet-stream');
            header('Content-Length: ' . (string)filesize($path));
            header('Content-Disposition: attachment; filename="' . $filename . '"');
            readfile($path);
            exit;
        } elseif ($action === 'delete_dump') {
            $accountName = strtoupper(trim((string)($_POST['account_name'] ?? '')));
            $filename = safeDumpName((string)($_POST['filename'] ?? ''));
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $accountName)) throw new RuntimeException('Invalid account name.');
            
            $path = $dumpDirectory . DIRECTORY_SEPARATOR . $accountName . DIRECTORY_SEPARATOR . $filename;
            if (is_file($path)) {
                unlink($path);
                $notice = "Backup {$filename} was deleted.";
            }
        } elseif ($action === 'create_backup') {
            if (!isWorldServerRunning()) throw new RuntimeException('The world server is not running.');
            $accountName = strtoupper(trim((string)($_POST['account_name'] ?? '')));
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $accountName)) throw new RuntimeException('Invalid account name.');
            
            $accountDir = $dumpDirectory . DIRECTORY_SEPARATOR . $accountName;
            if (!is_dir($accountDir)) @mkdir($accountDir, 0777, true);
            
            $charGuid = (int)($_POST['character_guid'] ?? 0);
            if ($charGuid <= 0) throw new RuntimeException('No valid character selected.');
            
            error_log("Nostalgia Backup: saving GUID {$charGuid} for account {$accountName} started.");
            
            // Validate character belongs to account
            $loginDb = loginDatabase($loginConfig);
            $stmt = $loginDb->prepare('SELECT id FROM account WHERE username = :usr');
            $stmt->execute(['usr' => $accountName]);
            $accId = $stmt->fetchColumn();
            if (!$accId) throw new RuntimeException('Account not found in the database.');
            
            $charDb = characterDatabase($worldConfig);
            $stmt = $charDb->prepare('SELECT name FROM characters WHERE guid = :guid AND account = :acc');
            $stmt->execute(['guid' => $charGuid, 'acc' => $accId]);
            $charName = $stmt->fetchColumn();
            if (!$charName) throw new RuntimeException('The character does not exist or does not belong to this account.');
            
            $tempFilename = 'temp_dump_' . $charGuid . '_' . time() . '.pdump';
            $tempPath = $serverDirectory . DIRECTORY_SEPARATOR . $tempFilename;
            
            $cmd = sprintf('pdump write %s %s', $tempFilename, $charName);
            error_log("Nostalgia Backup: Sende IPC Befehl: {$cmd}");
            
            if (sendWorldServerCommand($cmd)) {
                $found = false;
                for ($i = 0; $i < 20; $i++) {
                    usleep(250000); // 250ms
                    if (file_exists($tempPath) && filesize($tempPath) > 50) {
                        $found = true;
                        break;
                    }
                }
                
                if ($found) {
                    $finalFilename = $charName . '_' . date('Y-m-d_Hi') . '.pdump';
                    $finalPath = $accountDir . DIRECTORY_SEPARATOR . $finalFilename;
                    if (rename($tempPath, $finalPath)) {
                        error_log("Nostalgia Backup: Saved successfully as {$finalPath}.");
                        $notice = "Character '{$charName}' was backed up successfully.";
                    } else {
                        throw new RuntimeException('The backup could not be moved into the backup folder.');
                    }
                } else {
                    error_log("Nostalgia Backup: pdump Datei {$tempPath} was not created by the world server.");
                    throw new RuntimeException('Der Worldserver hat keine .pdump-Datei erzeugt. Bitte prÃ¼fen, ob pdump write existiert.');
                }
            } else {
                error_log("Nostalgia Backup: Could not send the IPC command through the named pipe.");
                throw new RuntimeException('Could not send the backup command to the world server.');
            }
        } elseif ($action === 'restore_backup') {
            if (!isWorldServerRunning()) throw new RuntimeException('The world server is not running.');
            $accountName = strtoupper(trim((string)($_POST['account_name'] ?? '')));
            $filename = safeDumpName((string)($_POST['filename'] ?? ''));
            $targetAccount = strtoupper(trim((string)($_POST['target_account'] ?? '')));
            
            if (!preg_match('/^[A-Z0-9]{3,16}$/', $accountName) || !preg_match('/^[A-Z0-9]{3,16}$/', $targetAccount)) {
                throw new RuntimeException('Invalid account name.');
            }
            
            $path = $dumpDirectory . DIRECTORY_SEPARATOR . $accountName . DIRECTORY_SEPARATOR . $filename;
            if (!is_file($path)) throw new RuntimeException('The backup was not found.');
            
            $oldTemps = glob($serverDirectory . DIRECTORY_SEPARATOR . 'temp_load_*.pdump');
            if (is_array($oldTemps)) {
                foreach ($oldTemps as $oldTemp) { @unlink($oldTemp); }
            }
            
            $tempFilename = 'temp_load_' . time() . '.pdump';
            $tempPath = $serverDirectory . DIRECTORY_SEPARATOR . $tempFilename;
            if (!copy($path, $tempPath)) throw new RuntimeException('The backup could not be copied into the temporary folder.');
            
            $cmd = sprintf('pdump load %s %s', $tempFilename, $targetAccount);
            error_log("Nostalgia Backup: Sende IPC Befehl: {$cmd}");
            
            if (sendWorldServerCommand($cmd)) {
                $notice = "Backup {$filename} is being restored to account {$targetAccount}.";
                usleep(500000);
            } else {
                @unlink($tempPath);
                throw new RuntimeException('Could not send the restore command.');
            }
        } elseif ($action === 'push_level_55') {
            $targetAccount = strtoupper(trim((string)($_POST['account_name'] ?? '')));
            $characterGuid = (int)($_POST['character_guid'] ?? 0);
            
            if ($targetAccount === '' || $characterGuid === 0) {
                throw new RuntimeException('No valid character selected.');
            }

            $loginDb = loginDatabase($loginConfig);
            $stmt = $loginDb->prepare('SELECT id FROM account WHERE username = :name');
            $stmt->execute(['name' => $targetAccount]);
            $accId = $stmt->fetchColumn();
            if ($accId === false) {
                throw new RuntimeException('Account not found.');
            }

            $charDb = characterDatabase($worldConfig);
            $stmt = $charDb->prepare('SELECT name, level, online FROM characters WHERE guid = :guid AND account = :acc');
            $stmt->execute(['guid' => $characterGuid, 'acc' => $accId]);
            $char = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$char) {
                throw new RuntimeException('Character not found or not owned by this account.');
            }
            
            if (!empty($char['online'])) {
                throw new RuntimeException('The character is currently online. Log out first.');
            }

            if ((int)$char['level'] >= 55) {
                throw new RuntimeException('This character is already level 55 or higher.');
            }

            $cName = $char['name'];
            $oldLevel = (int)$char['level'];
            
            $stmtUpdate = $charDb->prepare('UPDATE characters SET level = 55, xp = 0 WHERE guid = :guid AND account = :acc AND online = 0 LIMIT 1');
            $stmtUpdate->execute(['guid' => $characterGuid, 'acc' => $accId]);
            $affected = $stmtUpdate->rowCount();
            
            if ($affected > 0) {
                $notice = "{$cName} was raised from level {$oldLevel} to level 55.";
            } else {
                throw new RuntimeException("{$cName} could not be updated (0 rows affected).");
            }
        }
    } catch (Throwable $exception) {
        error_log('Nostalgia administration: ' . $exception->getMessage());
        $error = $exception instanceof PDOException
            ? 'The database is not available. Start the server or MariaDB first.'
            : $exception->getMessage();
    }
}

$selectedAccount = strtoupper(trim((string)($_REQUEST['account'] ?? '')));
$accountsList = [];
$accountCharacters = [];
$dumps = [];
if ($page === 'characters') {
    try {
        $loginDb = loginDatabase($loginConfig);
        $accountsList = $loginDb->query('SELECT id, username FROM account WHERE username NOT IN ("ADMIN", "AHBOT") ORDER BY username ASC')->fetchAll(PDO::FETCH_ASSOC);
        
        if ($selectedAccount !== '') {
            $accId = false;
            foreach ($accountsList as $acc) {
                if (strtoupper($acc['username']) === $selectedAccount) {
                    $accId = $acc['id'];
                    break;
                }
            }
            if ($accId !== false) {
                $charDb = characterDatabase($worldConfig);
                $stmt = $charDb->prepare('SELECT guid, name, race, class, level, online FROM characters WHERE account = :acc ORDER BY level DESC, name ASC');
                $stmt->execute(['acc' => $accId]);
                $accountCharacters = $stmt->fetchAll(PDO::FETCH_ASSOC);
                
                $accDir = $dumpDirectory . DIRECTORY_SEPARATOR . $selectedAccount;
                $dumps = is_dir($accDir) ? dumpFiles($accDir) : [];
            } else {
                $selectedAccount = '';
            }
        }
    } catch (Throwable $e) {
        $error = "Database error while loading accounts: " . $e->getMessage();
    }
}
$isServerRunning = isWorldServerRunning();
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Nostalgia Local Administration</title>
    <style>
        :root { color-scheme: dark; --bg:#07101e; --panel:#101d31; --line:#31445f; --gold:#e5b95e; --sky:#83c9ef; --text:#e6edf7; --muted:#9aa9bc; --good:#58d68d; --bad:#ff7b7b; }
        * { box-sizing:border-box; } body { margin:0; background:radial-gradient(circle at top,#142847 0,#07101e 48%); color:var(--text); font:15px/1.55 system-ui,Segoe UI,sans-serif; }
        a { color:var(--sky); } .wrap { max-width:1100px; margin:auto; padding:32px 20px 60px; } header { text-align:center; margin-bottom:28px; }
        .logo { max-width:420px; width:75%; max-height:150px; object-fit:contain; } h1,h2,h3 { color:var(--gold); margin-top:0; } nav { display:flex; flex-wrap:wrap; gap:10px; justify-content:center; margin-top:18px; }
        nav a,.button,button { border:1px solid var(--line); border-radius:10px; background:#17263c; color:var(--text); padding:10px 15px; text-decoration:none; font-weight:700; cursor:pointer; }
        nav a.active,button.primary { border-color:var(--gold); background:#4b3b1d; } button.danger { border-color:#974343; background:#4a2026; } button:disabled { opacity:.45; cursor:not-allowed; }
        .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:18px; } .card { background:linear-gradient(145deg,rgba(18,33,55,.98),rgba(8,16,29,.98)); border:1px solid var(--line); border-radius:16px; padding:24px; box-shadow:0 14px 35px #0005; }
        .notice,.error,.warning { padding:14px 17px; border-radius:10px; margin-bottom:18px; } .notice { border:1px solid #357c5c; background:#123c2b; color:#aef0cb; } .error { border:1px solid #874040; background:#431d25; color:#ffc0c0; } .warning { border:1px solid #8a6c2e; background:#3c3019; color:#ffe0a0; }
        label { display:block; margin:12px 0 5px; color:var(--sky); font-weight:700; } input,select { width:100%; border:1px solid var(--line); border-radius:9px; background:#07101e; color:var(--text); padding:11px 12px; }
        form.inline { display:inline; } table { width:100%; border-collapse:collapse; } th,td { text-align:left; padding:11px 8px; border-bottom:1px solid #293a52; } th { color:var(--sky); }
        .character { display:flex; align-items:center; gap:12px; border:1px solid var(--line); border-radius:10px; padding:12px; margin:8px 0; } .character input { width:auto; }
        .actions { display:flex; flex-wrap:wrap; gap:10px; margin-top:16px; } code { color:#ffe0a0; } .muted { color:var(--muted); } ul { padding-left:21px; } footer { color:#74849a; text-align:center; margin-top:32px; }
    </style>
</head>
<body><main class="wrap">
    <header>
        <img class="logo" src="assets/nostalgia-magic-logo.png" alt="Nostalgia">
        <p class="muted">Local account and character administration</p>
        <nav>
            <a class="<?= $page === 'home' ? 'active' : '' ?>" href="?page=home">Home</a>
            <a class="<?= $page === 'accounts' ? 'active' : '' ?>" href="?page=accounts">Accounts</a>
            <a class="<?= $page === 'characters' ? 'active' : '' ?>" href="?page=characters">Characters</a>
            <a class="<?= $page === 'attunements' ? 'active' : '' ?>" href="?page=attunements">Content Guide</a>
        </nav>
    </header>
    <?php if ($notice !== ''): ?><div class="notice" role="status"><?= h($notice) ?></div><?php endif; ?>
    <?php if ($error !== ''): ?><div class="error" role="alert"><?= h($error) ?></div><?php endif; ?>

    <?php if ($page === 'home'): ?>
    <section class="grid">
        <article class="card"><h2>Classic foundation</h2><p>Nostalgia uses vMaNGOS and targets the original World of Warcraft 1.12.1 experience: classic classes, talents, quests, professions and combat systems.</p></article>
        <article class="card"><h2>Solo and small-group play</h2><p>PartyBots, BattleBots, outdoor rivals, a shared auction house and ambient chat make a local Azeroth feel active. Major classic dungeons support up to 10 players when using a raid group.</p></article>
        <article class="card"><h2>Controller support</h2><p>DinoController provides movement, camera and frame navigation. DinoMacroManager adds 14 configurable spell-chain slots. Copy both AddOns into your own client and run the supplied bridge.</p></article>
        <article class="card"><h2>Standard content state</h2><p>ZG, AQ20 and AQ40 are locked. Zandalar/Yojamba rewards, AQ-only rewards, the Scepter chain and War Effort are disabled. Normal Silithus content remains available.</p></article>
        <article class="card"><h2>Your own client is required</h2><p>This release does not contain World of Warcraft. Use your own clean Vanilla 1.12.1 client and set <code>realmlist.wtf</code> to <code>set realmlist 127.0.0.1</code>.</p></article>
        <article class="card"><h2>Local tools</h2><p>Create accounts here, back up or restore characters with vMaNGOS <code>.pdump</code> files, and optionally raise an offline character to level 55 without granting gear or gold.</p></article>
    </section>

    <?php elseif ($page === 'accounts'): ?>
    <section class="grid">
        <article class="card"><h2>Create account</h2><p class="muted">Creates a normal player account using the same SRP6 method as the world-server console.</p>
            <form method="post" autocomplete="off"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="create_account"><input type="hidden" name="page" value="accounts">
                <label for="username">Account name</label><input id="username" name="username" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required>
                <label for="password">Password</label><input id="password" name="password" type="password" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required>
                <div class="actions"><button class="primary" type="submit">Create account</button></div>
            </form>
        </article>
        <article class="card"><h2>Delete empty account</h2><p class="muted">Only accounts without characters can be deleted here.</p>
            <form method="post" autocomplete="off" onsubmit="return confirm('Delete account ' + this.username.value.toUpperCase() + '?');"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="delete_account"><input type="hidden" name="page" value="accounts">
                <label for="delete_username">Account name</label><input id="delete_username" name="username" maxlength="16" pattern="[A-Za-z0-9]{3,16}" required>
                <label for="confirmation">Enter the same name to confirm</label><input id="confirmation" name="confirmation" maxlength="16" required>
                <div class="actions"><button class="danger" type="submit">Delete empty account</button></div>
            </form>
        </article>
    </section>

    <?php elseif ($page === 'characters'): ?>
    <?php if ($selectedAccount === ''): ?>
        <article class="card"><h2>Select account</h2><form method="get"><input type="hidden" name="page" value="characters"><select name="account" required><option value="">-- Select --</option><?php foreach ($accountsList as $acc): ?><option value="<?= h($acc['username']) ?>"><?= h($acc['username']) ?></option><?php endforeach; ?></select><div class="actions"><button class="primary" type="submit">Continue</button></div></form></article>
    <?php else: ?>
        <?php if (!$isServerRunning): ?><div class="warning">The world server is not running. Character backups and restores require it.</div><?php endif; ?>
        <article class="card"><h2>Characters for <?= h($selectedAccount) ?></h2><p><a href="?page=characters">Choose another account</a></p>
            <form method="post" id="charForm"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" id="formAction" value="create_backup"><input type="hidden" name="page" value="characters"><input type="hidden" name="account_name" value="<?= h($selectedAccount) ?>">
                <?php if (empty($accountCharacters)): ?><p class="muted">This account has no characters.</p><?php else: ?>
                <?php $classes=[1=>'Warrior',2=>'Paladin',3=>'Hunter',4=>'Rogue',5=>'Priest',7=>'Shaman',8=>'Mage',9=>'Warlock',11=>'Druid']; foreach ($accountCharacters as $char): ?>
                    <label class="character"><input type="radio" name="character_guid" value="<?= h((string)$char['guid']) ?>" data-level="<?= (int)$char['level'] ?>" data-online="<?= !empty($char['online']) ? '1' : '0' ?>" <?= $isServerRunning ? 'required' : 'disabled' ?>><span><strong><?= h($char['name']) ?></strong><br><span class="muted">Level <?= (int)$char['level'] ?> - <?= h($classes[$char['class']] ?? 'Unknown') ?><?= !empty($char['online']) ? ' (Online)' : '' ?></span></span></label>
                <?php endforeach; ?>
                <?php if ($isServerRunning): ?><div class="actions"><button class="primary" type="submit" onclick="document.getElementById('formAction').value='create_backup'">Save character backup</button><button type="submit" onclick="const c=document.querySelector('input[name=character_guid]:checked');if(!c){alert('Select a character first.');return false;}if(c.dataset.online==='1'){alert('Log the character out first.');return false;}if(parseInt(c.dataset.level)>=55){alert('This character is already level 55 or higher.');return false;}if(!confirm('Raise this character to level 55? No gear or gold will be granted.'))return false;document.getElementById('formAction').value='push_level_55'">Raise to level 55</button></div><?php endif; ?>
                <?php endif; ?>
            </form>
        </article>
        <article class="card"><h2>Backup files</h2>
            <?php if (empty($dumps)): ?><p class="muted">No backup files exist for this account.</p><?php else: ?><table><thead><tr><th>File</th><th>Size</th><th>Modified</th><th>Actions</th></tr></thead><tbody><?php foreach ($dumps as $dump): $name=basename($dump); ?><tr><td><?= h($name) ?></td><td><?= h(number_format((int)filesize($dump)/1024,1,'.',',')) ?> KB</td><td><?= h(date('Y-m-d H:i',(int)filemtime($dump))) ?></td><td>
                <form class="inline" method="post"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="download_dump"><input type="hidden" name="page" value="characters"><input type="hidden" name="account_name" value="<?= h($selectedAccount) ?>"><input type="hidden" name="filename" value="<?= h($name) ?>"><button type="submit">Download</button></form>
                <?php if ($isServerRunning): ?><form class="inline" method="post" onsubmit="return confirm('Restore this character into account <?= h($selectedAccount) ?>?');"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="restore_backup"><input type="hidden" name="page" value="characters"><input type="hidden" name="account_name" value="<?= h($selectedAccount) ?>"><input type="hidden" name="target_account" value="<?= h($selectedAccount) ?>"><input type="hidden" name="filename" value="<?= h($name) ?>"><button type="submit">Restore</button></form><?php endif; ?>
                <form class="inline" method="post" onsubmit="return confirm('Delete this backup?');"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="delete_dump"><input type="hidden" name="page" value="characters"><input type="hidden" name="account_name" value="<?= h($selectedAccount) ?>"><input type="hidden" name="filename" value="<?= h($name) ?>"><button class="danger" type="submit">Delete</button></form>
            </td></tr><?php endforeach; ?></tbody></table><?php endif; ?>
        </article>
        <article class="card"><h2>Add an external backup</h2><p class="muted">Upload a valid vMaNGOS .pdump file (maximum 10 MB) to this account's local backup store.</p><form method="post" enctype="multipart/form-data"><input type="hidden" name="csrf" value="<?= h($csrf) ?>"><input type="hidden" name="action" value="upload_dump"><input type="hidden" name="page" value="characters"><input type="hidden" name="account_name" value="<?= h($selectedAccount) ?>"><label for="pdump">.pdump file</label><input id="pdump" name="pdump" type="file" accept=".pdump,text/plain" required><div class="actions"><button class="primary" type="submit">Add backup</button></div></form></article>
    <?php endif; ?>

    <?php elseif ($page === 'attunements'): ?>
    <section class="grid">
        <article class="card"><h2>Nostalgia instance sizes</h2><ul><li>Maraudon, BRD, LBRS, UBRS, Scholomance and Stratholme support up to 10 players.</li><li>Groups above five players must use a raid group.</li><li>Molten Core, Onyxia, Blackwing Lair and Naxxramas remain classic 40-player raids.</li></ul></article>
        <article class="card"><h2>Locked content</h2><ul><li>Zul'Gurub and Yojamba/Zandalar ZG features are locked.</li><li>Ruins and Temple of Ahn'Qiraj are locked.</li><li>AQ-only rewards, War Effort and the Scepter/Gate Opening chain are disabled.</li><li>Normal Silithus quests and exploration remain available.</li></ul></article>
        <article class="card"><h2>Key attunements</h2><ul><li>Molten Core: complete Attunement to the Core.</li><li>Onyxia: complete your faction's attunement and carry the Drakefire Amulet.</li><li>Blackwing Lair: use the Orb of Ascension after completing Blackhand's Command.</li><li>Naxxramas: complete The Dread Citadel - Naxxramas through the Argent Dawn.</li></ul></article>
        <article class="card"><h2>Dungeon access</h2><ul><li>Scholomance: Skeleton Key or an appropriate lock-opening method.</li><li>Stratholme: main entrance is open; city and Scarlet keys provide shortcuts.</li><li>Dire Maul: East is open; Crescent Key opens West and North.</li><li>Maraudon: the Scepter of Celebras provides the inner portal shortcut.</li></ul></article>
    </section>
    <?php endif; ?>
    <footer>Nostalgia English Repack - local use</footer>
</main></body></html>
