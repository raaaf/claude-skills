{{-- Hero preset picker: two intentional a11y bugs in the SAME widget.
     1) Contrast: text-gray-400 on bg-gray-100 (fails 4.5:1)
     2) Radiogroup with roving tabindex but NO arrow-key handlers --}}
<div
    role="radiogroup"
    aria-label="Hero-Vorlage waehlen"
    x-data="{ selected: 'sunset' }"
    class="flex gap-2 rounded-lg bg-gray-100 p-2"
>
    <template x-for="preset in ['sunset', 'ocean', 'forest']" :key="preset">
        <div
            role="radio"
            :aria-checked="selected === preset"
            :tabindex="selected === preset ? 0 : -1"
            @click="selected = preset"
            class="cursor-pointer rounded-md px-3 py-2 text-sm text-gray-400"
            x-text="preset"
        ></div>
    </template>
</div>
