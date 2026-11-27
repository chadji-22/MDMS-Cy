<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');

$isAdmin = Auth::role() === 'SYSTEM_ADMIN';
$route = View::url('/staff/accounts.php');   // full URL path (base included)
$staffRoles = ['SYSTEM_OFFICER' => 'System officer', 'DSO' => 'DSO', 'TSO' => 'TSO'];
$organizationTypes = ['SUPPLIER' => 'Supplier', 'AGGREGATOR' => 'Aggregator'];
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $action = filter_input(INPUT_POST, 'action');
    if (!in_array($action, ['staff', 'organization', 'member'], true)) {
        View::fail(400, 'Invalid action', 'Choose an account or organization form.');
    }
    if ($action === 'staff') {
        Auth::requireRole('SYSTEM_ADMIN');
    }

    $name = trim((string) filter_input(INPUT_POST, 'name'));
    if (preg_match('/\A.{1,150}\z/u', $name) !== 1) {
        View::fail(400, 'Invalid name', 'Enter a name of up to 150 characters.');
    }

    try {
        if ($action === 'organization') {
            $type = filter_input(INPUT_POST, 'org_type');
            if (!isset($organizationTypes[$type])) {
                View::fail(400, 'Invalid type', 'Choose Supplier or Aggregator.');
            }
            Db::callAsActor('sp_CreateOrganization', [Db::nv($name, 150), $type]);
            View::flash('ok', 'Organization created.');
        } else {
            $email = trim((string) filter_input(INPUT_POST, 'email'));
            $password = (string) filter_input(INPUT_POST, 'password');
            $phone = trim((string) filter_input(INPUT_POST, 'phone'));
            if (strlen($email) > 255 || !filter_var($email, FILTER_VALIDATE_EMAIL)
                || preg_match('/\A.{8,128}\z/u', $password) !== 1
                || preg_match('/\A[+0-9(). -]{0,20}\z/', $phone) !== 1) {
                View::fail(400, 'Invalid account details', 'Enter a valid email, a password of 8 to 128 characters and an optional phone number.');
            }
            $identity = [$email, Db::nv($password, 128), Db::nv($name, 150), $phone === '' ? null : $phone];

            if ($action === 'staff') {
                $role = filter_input(INPUT_POST, 'role');
                if (!isset($staffRoles[$role])) {
                    View::fail(400, 'Invalid role', 'Choose System officer, DSO or TSO.');
                }
                Db::callAsActor('sp_CreateStaffUser', [...$identity, $role]);
                View::flash('ok', 'Staff account created.');
            } else {
                $organization = filter_input(INPUT_POST, 'organization_id', FILTER_VALIDATE_INT, [
                    'options' => ['min_range' => 1, 'max_range' => 2147483647],
                ]);
                if (!$organization) {
                    View::fail(400, 'Invalid organization', 'Select an organization.');
                }
                Db::callAsActor('sp_CreateOrganizationUser', [$organization, ...$identity]);
                View::flash('ok', 'Organization account created.');
            }
        }
        header('Location: ' . $route, true, 303);
        exit;
    } catch (DbError $exception) {
        $error = $exception;
        http_response_code($error->httpStatus());
    }
}

$organizations = [];
$listError = null;
try {
    $organizations = Db::rows('sp_ListOrganizations');
} catch (DbError $exception) {
    $listError = $exception;
}

// E-12: the list of accounts (filters by role, approval status and a name / email search; 50 per page)
$roles = ['SYSTEM_ADMIN' => 'System admin', 'SYSTEM_OFFICER' => 'System officer', 'DSO' => 'DSO', 'TSO' => 'TSO',
          'SUPPLIER' => 'Supplier', 'AGGREGATOR' => 'Aggregator', 'TECHNICIAN' => 'Technician', 'CONSUMER' => 'Consumer'];
$approvalStatuses = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'];
$filterRole = filter_input(INPUT_GET, 'role');
$filterRole = isset($roles[$filterRole]) ? $filterRole : null;
$filterStatus = filter_input(INPUT_GET, 'status');
$filterStatus = in_array($filterStatus, $approvalStatuses, true) ? $filterStatus : null;
$search = trim((string) filter_input(INPUT_GET, 'q'));
$search = preg_match('/\A.{1,100}\z/u', $search) === 1 ? $search : '';
$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 50;
$users = [];
$usersError = null;
try {
    $users = Db::rows('sp_ListUsers', [$filterRole, $filterStatus, $search === '' ? null : Db::nv($search, 100), $page, $pageSize]);
} catch (DbError $exception) {
    $usersError = $exception;
}
$pageLink = static fn (int $number): string => '?' . http_build_query(
    ['role' => $filterRole, 'status' => $filterStatus, 'q' => $search === '' ? null : $search, 'page' => $number]);

$accountFields = static function (): void {
    ?>
    <label>Full name <input name="name" maxlength="150" required></label>
    <label>Email <input name="email" type="email" maxlength="255" autocomplete="off" required></label>
    <label>Initial password <input name="password" type="password" minlength="8" maxlength="128" autocomplete="new-password" required></label>
    <label>Phone (optional) <input name="phone" type="tel" maxlength="20"></label>
    <?php
};

View::header('Accounts and organizations');
if ($error !== null) {
    View::error($error);
}
?>
<h2>Organizations</h2>
<?php if ($listError !== null): ?>
    <?php View::error($listError); ?>
<?php elseif ($organizations === []): ?>
    <p>No organizations yet.</p>
<?php else: ?>
    <table>
        <thead><tr><th>ID</th><th>Name</th><th>Type</th></tr></thead>
        <tbody>
        <?php foreach ($organizations as $organization): ?>
            <tr>
                <td><?= View::h($organization['organization_id']) ?></td>
                <td><?= View::h($organization['name']) ?></td>
                <td><?= View::h($organizationTypes[$organization['org_type']] ?? $organization['org_type']) ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>

<h2>Accounts</h2>
<form method="get" action="<?= View::base() ?>/staff/accounts.php" class="card">
    <label>Role
        <select name="role">
            <option value="">All roles</option>
            <?php foreach ($roles as $value => $label): ?>
                <option value="<?= View::h($value) ?>" <?= $filterRole === $value ? 'selected' : '' ?>><?= View::h($label) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <label>Approval
        <select name="status">
            <option value="">All statuses</option>
            <?php foreach ($approvalStatuses as $option): ?>
                <option value="<?= View::h($option) ?>" <?= $filterStatus === $option ? 'selected' : '' ?>><?= View::h($option) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <label>Name or email <input name="q" maxlength="100" value="<?= View::h($search) ?>"></label>
    <button type="submit">Filter accounts</button>
</form>
<?php if ($usersError !== null): ?>
    <?php View::error($usersError); ?>
<?php elseif ($users === []): ?>
    <p>No matching accounts on this page.</p>
<?php else: ?>
    <table>
        <thead><tr><th>ID</th><th>Name</th><th>Email</th><th>Role</th><th>Organization</th><th>Approval</th><th>Active</th><th>Created (UTC)</th></tr></thead>
        <tbody>
        <?php foreach ($users as $user): ?>
            <tr>
                <td><?= View::h($user['user_id']) ?></td>
                <td><?= View::h($user['full_name']) ?></td>
                <td><?= View::h($user['email']) ?></td>
                <td><?= View::h($roles[$user['role_code']] ?? $user['role_code']) ?></td>
                <td><?= View::h($user['organization_name'] ?? '—') ?></td>
                <td><?= View::h($user['approval_status']) ?></td>
                <td><?= $user['anonymized_at'] !== null ? 'forgotten (GDPR)' : ((int) $user['is_active'] === 1 ? 'yes' : 'no') ?></td>
                <td><?= View::h($user['created_at']) ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php if ($usersError === null && ($page > 1 || count($users) === $pageSize)): ?>
    <p>
        <?php if ($page > 1): ?><a href="<?= View::h($pageLink($page - 1)) ?>">Previous page</a><?php endif; ?>
        <?php if (count($users) === $pageSize): ?><a href="<?= View::h($pageLink($page + 1)) ?>">Next page</a><?php endif; ?>
    </p>
<?php endif; ?>

<?php if ($isAdmin): ?>
    <h2>Create staff account</h2>
    <form method="post" action="<?= View::h($route) ?>" class="card">
        <?= Csrf::field() ?>
        <input type="hidden" name="action" value="staff">
        <?php $accountFields(); ?>
        <label>Role
            <select name="role" required>
                <option value="">Select a role</option>
                <?php foreach ($staffRoles as $value => $label): ?>
                    <option value="<?= View::h($value) ?>"><?= View::h($label) ?></option>
                <?php endforeach; ?>
            </select>
        </label>
        <button type="submit">Create staff account</button>
    </form>
<?php endif; ?>

<h2>Create organization</h2>
<form method="post" action="<?= View::h($route) ?>" class="card">
    <?= Csrf::field() ?>
    <input type="hidden" name="action" value="organization">
    <label>Organization name <input name="name" maxlength="150" required></label>
    <label>Type
        <select name="org_type" required>
            <option value="">Select a type</option>
            <?php foreach ($organizationTypes as $value => $label): ?>
                <option value="<?= View::h($value) ?>"><?= View::h($label) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <button type="submit">Create organization</button>
</form>

<h2>Create organization account</h2>
<?php if ($listError !== null): ?>
    <?php View::error($listError); ?>
<?php elseif ($organizations === []): ?>
    <p>Create an organization before adding an account.</p>
<?php else: ?>
    <form method="post" action="<?= View::h($route) ?>" class="card">
        <?= Csrf::field() ?>
        <input type="hidden" name="action" value="member">
        <label>Organization
            <select name="organization_id" required>
                <option value="">Select an organization</option>
                <?php foreach ($organizations as $organization): ?>
                    <option value="<?= View::h($organization['organization_id']) ?>"><?= View::h($organization['name']) ?> (<?= View::h($organizationTypes[$organization['org_type']]) ?>)</option>
                <?php endforeach; ?>
            </select>
        </label>
        <?php $accountFields(); ?>
        <button type="submit">Create organization account</button>
    </form>
<?php endif; ?>
<?php View::footer(); ?>
