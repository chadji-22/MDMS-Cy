<?php
declare(strict_types=1);

namespace Mdms;

/**
 * The navigation menu is the sum of one small file per area: areas/<area>/menu.php returns a list of
 *     ['label' => 'My premises', 'href' => '/consumer/premises.php', 'roles' => ['CONSUMER']]
 * The shared layout shows only the items whose roles contain the logged-in user's role. Each area owner edits
 * only the menu.php of their own area, so nobody collides in a shared file. A menu entry is a convenience only:
 * the page itself must still call Auth::requireRole(), and the procedures check the role again.
 */
final class Menu
{
    /** @return array<int,array{label:string,href:string}>  href is a full URL path (base included) */
    public static function forRole(string $role): array
    {
        $items = [];
        $files = glob(dirname(__DIR__) . '/areas/*/menu.php') ?: [];
        sort($files);
        foreach ($files as $file) {
            foreach ((array) require $file as $item) {
                if (isset($item['label'], $item['href'], $item['roles']) && in_array($role, (array) $item['roles'], true)) {
                    // menu files hold application paths; the base (sub-folder) is added here
                    $items[] = ['label' => (string) $item['label'], 'href' => View::url((string) $item['href'])];
                }
            }
        }
        return $items;
    }
}
