//
//  NowPlaying.swift
//  Max Q
//
//  What's playing, and control over it from anywhere in the window. A small script in Max Q's
//  isolated world tells the tab when its page starts or stops playing sound or video; the tab's row
//  shows a speaker (a click mutes it), and while a tab that isn't on screen plays, a card at the
//  foot of the sidebar shows it with play and pause, mute, picture in picture, and the way back
//  to it.
//

import AppKit
import SwiftUI
import WebKit

/// The page script: reports whether anything on the page is playing (and muted, and a video).
enum MediaScript {
    static let handlerName = "maxqMedia"

    static let source = """
    (function () {
      if (window.__maxqMedia) return;
      window.__maxqMedia = true;
      var last = '';
      function report() {
        var media = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
        var playing = media.filter(function (m) { return !m.paused && !m.ended && m.readyState > 2; });
        var state = {
          playing: playing.length > 0,
          muted: playing.length > 0 && playing.every(function (m) { return m.muted || m.volume === 0; }),
          video: playing.some(function (m) { return m.tagName === 'VIDEO' && m.videoWidth > 0; }),
          paused: media.some(function (m) { return m.paused && m.currentTime > 0 && !m.ended; })
        };
        var key = JSON.stringify(state);
        if (key === last) return;
        last = key;
        try { window.webkit.messageHandlers.\(handlerName).postMessage(state); } catch (e) {}
      }
      ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied'].forEach(function (name) {
        document.addEventListener(name, report, true);
      });
    })();
    """

    static func install(in configuration: WKWebViewConfiguration) {
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(MediaHandler.shared, contentWorld: .defaultClient, name: handlerName)
    }

    // MARK: Control

    /// Pauses what's playing, or plays what was paused.
    @MainActor
    static func togglePlayback(in webView: WKWebView) async {
        _ = await PageScripts.run("""
        var media = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
        var playing = media.filter(function (m) { return !m.paused && !m.ended; });
        if (playing.length) { playing.forEach(function (m) { m.pause(); }); return 'paused'; }
        var paused = media.filter(function (m) { return m.paused && m.currentTime > 0 && !m.ended; });
        if (paused.length) { try { await paused[0].play(); } catch (e) {} return 'playing'; }
        return 'none';
        """, in: webView)
    }

    @MainActor
    static func setMuted(_ muted: Bool, in webView: WKWebView) async {
        _ = await PageScripts.run("""
        document.querySelectorAll('video, audio').forEach(function (m) { m.muted = muted; });
        return true;
        """, arguments: ["muted": muted], in: webView)
    }

    /// The playing video in a floating window of its own, over every app. A page only lets a video
    /// float from a click inside it, so Max Q puts a "Float video" button on the video itself; the
    /// click on it floats the video.
    @MainActor
    static func pictureInPicture(in webView: WKWebView) async -> Bool {
        let result = await PageScripts.run("""
        var videos = Array.prototype.slice.call(document.querySelectorAll('video'));
        var video = videos.find(function (v) { return !v.paused && v.videoWidth > 0; }) || videos.find(function (v) { return v.videoWidth > 0; });
        if (!video) return 'none';
        if (document.pictureInPictureElement) { try { await document.exitPictureInPicture(); return 'closed'; } catch (e) {} }
        var old = document.getElementById('__maxq-float');
        if (old) old.remove();
        var r = video.getBoundingClientRect();
        var button = document.createElement('button');
        button.id = '__maxq-float';
        button.textContent = label;
        button.style.cssText = 'position:fixed;z-index:2147483647;left:' + Math.round(r.left + r.width / 2) + 'px;top:' +
          Math.round(r.top + r.height / 2) + 'px;transform:translate(-50%,-50%);padding:10px 18px;border:0;border-radius:999px;' +
          'background:rgba(10,10,10,0.82);color:#fff;font:600 14px -apple-system,system-ui,sans-serif;cursor:pointer;' +
          'box-shadow:0 8px 24px rgba(0,0,0,0.35);backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px)';
        button.addEventListener('click', function (e) {
          e.preventDefault(); e.stopPropagation();
          button.remove();
          // WebKit's own floating mode first, at once, while the click still counts.
          try {
            if (video.webkitSupportsPresentationMode && video.webkitSupportsPresentationMode('picture-in-picture')) {
              video.webkitSetPresentationMode('picture-in-picture');
              return;
            }
          } catch (err) {}
          try { video.disablePictureInPicture = false; video.requestPictureInPicture().catch(function () {}); } catch (err) {}
        }, true);
        document.documentElement.appendChild(button);
        setTimeout(function () { button.remove(); }, 7000);
        return 'offered';
        """, arguments: ["label": String(localized: "Float video")], in: webView) as? String
        return result == "offered" || result == "closed"
    }
}

final class MediaHandler: NSObject, WKScriptMessageHandler {
    static let shared = MediaHandler()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView as? MaxQWebView, let tab = webView.tab,
              let body = message.body as? [String: Any] else { return }
        let playing = body["playing"] as? Bool ?? false
        withAnimation(Motion.smooth) {
            tab.media = TabMedia(playing: playing, muted: body["muted"] as? Bool ?? false,
                                 video: body["video"] as? Bool ?? false,
                                 paused: !playing && (body["paused"] as? Bool ?? false))
        }
    }
}

/// What a tab's page is playing.
struct TabMedia: Equatable {
    var playing = false
    var muted = false
    var video = false
    /// Something was playing and is paused (the card stays, with a play button).
    var paused = false

    var isActive: Bool { playing || paused }
}

// MARK: - The card

/// At the foot of the sidebar while a tab that isn't on screen is playing (or paused mid-way).
struct NowPlayingCard: View {
    @Bindable var browser: BrowserModel

    private var tab: BrowserTab? {
        browser.allTabs.first { $0.media.playing && $0.id != browser.selectedTabID }
            ?? browser.allTabs.first { $0.media.paused && $0.id != browser.selectedTabID }
    }

    var body: some View {
        if let tab {
            HStack(spacing: 10) {
                Button { browser.select(tab) } label: {
                    HStack(spacing: 9) {
                        TabIcon(tab: tab, size: 16)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.displayTitle)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(tab.media.playing ? (tab.media.muted ? "Playing, muted" : "Playing") : "Paused")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip("Go to the tab")
                if let webView = tab.webView {
                    Button { Task { await MediaScript.togglePlayback(in: webView) } } label: {
                        Icon(tab.media.playing ? .stop : .play, size: 13)
                    }
                    .iconButton(size: 26)
                    .accessibilityLabel(tab.media.playing ? "Pause" : "Play")
                    Button { Task { await MediaScript.setMuted(!tab.media.muted, in: webView) } } label: {
                        Icon(tab.media.muted ? .speakerOff : .speaker, size: 14)
                    }
                    .iconButton(size: 26)
                    .accessibilityLabel(tab.media.muted ? "Unmute" : "Mute")
                    if tab.media.video {
                        Button {
                            Task {
                                // The button appears on the video in its tab: go there to click it.
                                browser.select(tab)
                                if !(await MediaScript.pictureInPicture(in: webView)) {
                                    browser.showToast(String(localized: "This page has no video to float."))
                                }
                            }
                        } label: { Icon(.pip, size: 14) }
                        .iconButton(size: 26)
                        .tip("Picture in picture")
                        .accessibilityLabel("Picture in Picture")
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
