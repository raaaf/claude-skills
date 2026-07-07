{{-- Diff-Kontext: resources/views/components/inline-stepper.blade.php wechselte
     sein value-Prop von Text auf numerisch: @props(['value' => 0]) mit
     (int) $value Cast im Component-Body. Diese Call-Site blieb unveraendert. --}}
<x-inline-stepper
    :label="__('tasks.progress')"
    :value="$task->done_count . '/' . $task->total_count"
/>
