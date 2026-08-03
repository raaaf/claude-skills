<?php

namespace App\Jobs;

use App\Models\DigestBatch;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class BuildNotificationDigest implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /** @var array<string, mixed> */
    public array $payload = [];

    public bool $wasAggregated = false;

    public function __construct(public DigestBatch $batch) {}

    public function handle(): void
    {
        $this->payload = [
            'batch_id' => $this->batch->id,
            'entries' => $this->collectEntries(),
            'digest_ready' => true,
        ];

        $this->wasAggregated = true;

        $this->finalize();
    }

    /** @return array<int, array<string, mixed>> */
    private function collectEntries(): array
    {
        return $this->batch->pendingNotifications()
            ->get()
            ->map(fn ($n) => ['id' => $n->id, 'type' => $n->notification_type])
            ->all();
    }

    private function finalize(): void
    {
        // Rebuilds the payload from the batch again — everything handle() just
        // wrote (including digest_ready) is discarded before anyone read it.
        $this->payload = [
            'batch_id' => $this->batch->id,
            'entries' => $this->batch->pendingNotifications()
                ->get()
                ->map(fn ($n) => ['id' => $n->id])
                ->all(),
        ];

        $this->batch->update(['digest_payload' => $this->payload]);
    }
}
