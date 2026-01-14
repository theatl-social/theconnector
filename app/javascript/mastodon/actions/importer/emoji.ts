import type { ApiCustomEmojiJSON } from '@/mastodon/api_types/custom_emoji';

export async function importCustomEmoji(emojis: ApiCustomEmojiJSON[]) {
  if (emojis.length === 0) {
    return;
  }

  // First, check if we already have them all.
  const { searchCustomEmojisByShortcodes, clearEtag } = await import(
    '@/mastodon/features/emoji/database'
  );

  const existingEmojis = await searchCustomEmojisByShortcodes(
    emojis.map((emoji) => emoji.shortcode),
  );

  // If there's a mismatch, re-import all custom emojis.
  if (existingEmojis.length < emojis.length) {
    await clearEtag('custom');
    const { importCustomEmojiData } = await import(
      '@/mastodon/features/emoji/loader'
    );
    await importCustomEmojiData();
  }
}
