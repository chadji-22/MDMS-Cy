<?php
declare(strict_types=1);

namespace Mdms;

/**
 * An error from the database, already translated for the user. Pages catch it, show getUserMessage() and,
 * if they need to branch, look at category() (never at the raw SQL text, which is only written to the server log).
 */
final class DbError extends \RuntimeException
{
    public const NOT_FOUND  = 'not_found';    // 50001
    public const PERMISSION = 'permission';   // 50002
    public const STATE      = 'state';        // 50003 wrong state, e.g. the request was already handled
    public const INPUT      = 'input';        // 50004
    public const DUPLICATE  = 'duplicate';    // 50005
    public const LOGIN      = 'login';        // 50006
    public const BUSY       = 'busy';         // 50007
    public const HISTORY    = 'history';      // 50008 past data not bought
    public const GUARD      = 'guard';        // [51001]..[51012] a rule enforced by a trigger
    public const SERVER     = 'server';       // anything else: connection, driver, unexpected

    private string $category;
    private int $sqlCode;
    private int $httpStatus;
    private string $userMessage;
    private string $reference;

    public function __construct(string $category, int $sqlCode, int $httpStatus, string $userMessage, string $reference = '')
    {
        parent::__construct($userMessage, $sqlCode);
        $this->category = $category;
        $this->sqlCode = $sqlCode;
        $this->httpStatus = $httpStatus;
        $this->userMessage = $userMessage;
        $this->reference = $reference;
    }

    public function category(): string { return $this->category; }
    /** 50001-50008, 51001-51012, or 0 when it is not one of the project's own errors. */
    public function sqlCode(): int { return $this->sqlCode; }
    public function httpStatus(): int { return $this->httpStatus; }
    public function getUserMessage(): string { return $this->userMessage; }
    /** Short id that is also in the server log, for "server" errors. */
    public function reference(): string { return $this->reference; }
}
