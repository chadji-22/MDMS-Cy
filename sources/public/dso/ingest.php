<?php
/**
 * B7 · DSO / officer · Ingest one telemetry packet or a batch, pasted as JSON
 * [project.pdf §3.1 p.8; Appendix p.15; UC-15]   sp_IngestTelemetryPacket, sp_IngestTelemetryBatch
 * A wrong packet is not refused: the database keeps it (COMM_ERROR / UNMATCHED / QUARANTINED) and raises an event.
 * sp_IngestTelemetryPacket has no actor (mechanism INGESTION: the meter or the head-end sends the packet), so this page
 * is the guard for a single packet; the batch procedure checks the role itself.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Upload, Validate, View};

Auth::requireRole('DSO', 'SYSTEM_OFFICER');

$error = null;
$payload = '';
$mode = 'packet';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Upload::rejectOversized();
    Csrf::verify();
    $payload = Validate::post('payload');
    $mode = Validate::post('mode') === 'batch' ? 'batch' : 'packet';
    try {
        if (trim($payload) === '' || preg_match('//u', $payload) !== 1) {
            throw Ui::invalid('paste a packet (UTF-8 text).');
        }
        if ($mode === 'packet') {
            if (Validate::utf16Length($payload) > 4000) {
                throw Ui::invalid('a packet may have at most 4000 characters.');
            }
            $result = Db::row('sp_IngestTelemetryPacket', [Db::nv($payload, 4000)], false);
        } else {
            if (strlen($payload) > 2 * 1024 * 1024) {
                throw Ui::invalid('a batch may have at most 2 MB.');
            }
            $result = Db::row('sp_IngestTelemetryBatch', [Db::nvMax($payload)]);
        }
        Ui::keep('ingest', ['mode' => $mode, 'result' => $result ?? []]);
        Ui::redirect('/dso/ingest.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$done = Ui::kept('ingest');
$example = json_encode([
    'Meter_Network_ID' => 'DEMO-NET-001', 'Transmission_Timestamp' => gmdate('Y-m-d\TH:i:s\Z', intdiv(time(), 900) * 900),
    'Cell_Signal_Strength_dBm' => -92, 'Network_Type' => 'NB_IOT',
    'Telemetry_Payload' => [['obis' => '1.8.0', 'value' => 1000.5, 'unit' => 'kWh'], ['obis' => '32.7.0', 'value' => 231, 'unit' => 'V']],
], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

View::header('Ingest telemetry');
if ($error) {
    View::error($error);
}
if ($done !== null):
    $r = $done['result'];
    if ($done['mode'] === 'packet'): ?>
  <p class="flash ok" role="status">Packet <?= (int) ($r['packet_id'] ?? 0) ?> stored: <?= Ui::badge((string) ($r['match_status'] ?? '')) ?>,
    <?= (int) ($r['readings_inserted'] ?? 0) ?> readings.</p>
  <?php else: ?>
  <p class="flash ok" role="status">Batch stored: <?= (int) ($r['packets'] ?? 0) ?> packets, <?= (int) ($r['matched'] ?? 0) ?> matched,
    <?= (int) ($r['unmatched'] ?? 0) ?> unmatched, <?= (int) ($r['quarantined'] ?? 0) ?> quarantined,
    <?= (int) ($r['comm_error'] ?? 0) ?> communication errors, <?= (int) ($r['errors'] ?? 0) ?> failed;
    <?= (int) ($r['readings_inserted'] ?? 0) ?> readings.</p>
  <?php endif; ?>
<?php endif; ?>
<form method="post" action="<?= View::base() ?>/dso/ingest.php" class="card wide">
  <?= Csrf::field() ?>
  <div class="row">
    <label class="check"><input type="radio" name="mode" value="packet" <?= $mode === 'packet' ? 'checked' : '' ?>> One packet</label>
    <label class="check"><input type="radio" name="mode" value="batch" <?= $mode === 'batch' ? 'checked' : '' ?>> Batch: a JSON array of packets</label>
  </div>
  <label>JSON <textarea name="payload" rows="14" spellcheck="false" required><?= View::h($payload) ?></textarea></label>
  <button type="submit">Ingest</button>
</form>
<p class="muted">MATCHED = the meter exists and is active. UNMATCHED = unknown network id. QUARANTINED = the meter is not active.
  COMM_ERROR = not a valid packet. Nothing is lost: every packet is stored, and the readings wait for VEE.</p>
<h2>Example</h2>
<pre class="card wide"><?= View::h($example) ?></pre>
<?php
View::footer();
