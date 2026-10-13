/*
 * maxqTranscript: the transcript of the YouTube video on screen, read from YouTube's own
 * transcript panel once the user has opened it (under the video: "...more", then "Show
 * transcript"). Nothing is requested from YouTube: the script reads what the page already shows,
 * the way "Summarize this page" reads a page's text.
 *
 * Usage, as a callAsyncJavaScript body:
 *     <this file's source>
 *     return await maxqTranscript(options);
 *
 * Returns
 *   { videoId, title, author, lengthSeconds, language: null,
 *     segments: [{ start, text }] }        // start in seconds
 *
 * Throws an Error whose `code` is NOT_A_VIDEO_PAGE, PANEL_CLOSED or EMPTY_TRANSCRIPT.
 *
 * Verified 2026-10-11 against youtube.com's panel: rows are <transcript-segment-view-model> with
 * a ".ytwTranscriptSegmentViewModelTimestamp" ("0:01") and the words in a
 * "span.ytAttributedStringHost"; the older <ytd-transcript-segment-renderer> (".segment-timestamp",
 * ".segment-text") is read too.
 */
async function maxqTranscript(options) {
  function fail(code, message) {
    const error = new Error(message);
    error.code = code;
    return error;
  }

  function videoId() {
    const url = new URL(location.href);
    if (url.pathname === '/watch') return url.searchParams.get('v');
    const match = url.pathname.match(/^\/(shorts|live|embed)\/([A-Za-z0-9_-]{6,20})/);
    return match ? match[2] : null;
  }

  function seconds(stamp) {
    const parts = stamp.trim().split(':').map(Number);
    if (parts.length < 2 || parts.length > 3 || parts.some(isNaN)) return null;
    return parts.reduce((total, part) => total * 60 + part, 0);
  }

  const id = videoId();
  if (!id) throw fail('NOT_A_VIDEO_PAGE', 'This page is not a video.');

  const rows = document.querySelectorAll('transcript-segment-view-model, ytd-transcript-segment-renderer');
  if (!rows.length) throw fail('PANEL_CLOSED', 'The transcript panel is not open.');

  const segments = [];
  for (const row of rows) {
    const stampNode = row.querySelector('.ytwTranscriptSegmentViewModelTimestamp, .segment-timestamp');
    const textNode = row.querySelector('span.ytAttributedStringHost, .segment-text, yt-formatted-string');
    let stamp = stampNode ? stampNode.textContent : '';
    let text = textNode ? textNode.textContent : '';
    if (!stamp || !text) {
      // Whatever the markup: the time is the line that reads like one, the words are the last line.
      const lines = (row.innerText || '').split('\n').map((line) => line.trim()).filter(Boolean);
      stamp = stamp || lines.find((line) => /^\d+(:\d{2}){1,2}$/.test(line)) || '';
      text = text || lines.filter((line) => !/^\d+(:\d{2}){1,2}$/.test(line)).pop() || '';
    }
    const start = seconds(stamp);
    text = text.replace(/\s+/g, ' ').trim();
    if (start !== null && text) segments.push({ start, text });
  }
  if (!segments.length) throw fail('EMPTY_TRANSCRIPT', 'The transcript panel is empty.');

  const video = document.querySelector('video');
  const channel = document.querySelector('#owner #channel-name a, ytd-channel-name a, #upload-info #channel-name a');
  return {
    videoId: id,
    title: document.title.replace(/\s*-\s*YouTube\s*$/, ''),
    author: channel ? channel.textContent.trim() : null,
    lengthSeconds: video && isFinite(video.duration) ? video.duration : null,
    language: null,
    segments,
  };
}
