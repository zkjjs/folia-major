import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { motionValue } from 'framer-motion';
import '../../src/i18n/config';
import '../../src/index.css';
import Visualizer from '../../src/components/visualizer/classic/Visualizer';
import { parseLyricsByFormat, type LyricParseFormat } from '../../src/utils/lyrics/parserCore';
import type { Line, Theme, AudioBands } from '../../src/types';
// Adapter for the original Folia renderer: AVPlayer supplies time; this page never creates audio.
type Snapshot = {
    id: string; time: number; duration: number; playing: boolean; active: boolean; dark: boolean;
    title?: string; artist?: string; lyric?: string;
};
declare global {
    interface Window {
        FoliaNative: { receive: (snapshot: Snapshot) => void };
        webkit?: { messageHandlers: { folia: { postMessage: (value: object) => void } } };
    }
}
const clock = motionValue(0);
const zero = motionValue(0);
const bands: AudioBands = { bass: zero, lowMid: zero, mid: zero, vocal: zero, treble: zero };
const theme: Theme = {
    name: 'Folia iOS', backgroundColor: '#101127', primaryColor: '#f8f8ff',
    accentColor: '#b0a3ff', secondaryColor: '#a6b4db', fontStyle: 'sans', animationIntensity: 'calm',
};
const detectFormat = (text: string): LyricParseFormat => {
    if (text.trimStart().startsWith('<')) return 'ttml';
    if (/^WEBVTT/m.test(text)) return 'vtt';
    if (/\[\d+,\d+\]/.test(text)) return 'yrc';
    if (/<\d{2,3}:\d{2}[.:]\d{2,3}>/.test(text)) return 'enhanced-lrc';
    return 'lrc';
};
function LyricPage() {
    const [metadata, setMetadata] = useState({ id: '', title: '', artist: '', text: '', lines: [] as Line[] });
    const [lineIndex, setLineIndex] = useState(-1);
    const [paused, setPaused] = useState(true);
    const [active, setActive] = useState(true);
    const latest = useRef<Snapshot | null>(null);
    const lines = useRef<Line[]>([]);
    const anchor = useRef(0);
    const frame = useRef<number | null>(null);
    const lineRef = useRef(-1);
    useEffect(() => {
        const setClock = (value: number) => {
            clock.set(value);
            // Binary search also handles backward seeks without walking the whole lyric file.
            let left = 0, right = lines.current.length - 1, found = -1;
            while (left <= right) {
                const middle = (left + right) >> 1;
                if (lines.current[middle].startTime <= value) { found = middle; left = middle + 1; }
                else { right = middle - 1; }
            }
            if (found !== lineRef.current) { lineRef.current = found; setLineIndex(found); }
        };
        const tick = () => {
            const snapshot = latest.current;
            if (!snapshot || !snapshot.active || !snapshot.playing) { frame.current = null; return; }
            const projected = snapshot.time + Math.min(0.6, Math.max(0, (performance.now() - anchor.current) / 1000));
            setClock(snapshot.duration > 0 ? Math.min(snapshot.duration, projected) : projected);
            frame.current = requestAnimationFrame(tick);
        };
        window.FoliaNative = {
            receive(snapshot) {
                if (!snapshot || !Number.isFinite(snapshot.time) || !Number.isFinite(snapshot.duration)) return;
                // A new identity requires its metadata in the same message.
                if (latest.current?.id !== snapshot.id && typeof snapshot.lyric !== 'string') return;
                latest.current = snapshot; anchor.current = performance.now();
                if (typeof snapshot.lyric === 'string') {
                    let parsed: Line[] = [];
                    try {
                        parsed = parseLyricsByFormat(detectFormat(snapshot.lyric), snapshot.lyric).lines;
                    } catch {
                        window.webkit?.messageHandlers.folia.postMessage({ type: 'error', id: snapshot.id });
                    }
                    lines.current = parsed;
                    lineRef.current = -2;
                    setMetadata({ id: snapshot.id, title: snapshot.title ?? '', artist: snapshot.artist ?? '', text: snapshot.lyric, lines: parsed });
                }
                setClock(snapshot.time);
                setPaused(!snapshot.playing || !snapshot.active);
                setActive(snapshot.active);
                if (frame.current !== null) cancelAnimationFrame(frame.current);
                frame.current = snapshot.active && snapshot.playing ? requestAnimationFrame(tick) : null;
            },
        };
        window.webkit?.messageHandlers.folia.postMessage({ type: 'ready' });
        return () => {
            if (frame.current !== null) cancelAnimationFrame(frame.current);
        };
    }, []);
    const untimed = metadata.text.trim().length > 0 && metadata.lines.length === 0;
    return <div style={{ position: 'fixed', inset: 0, background: 'radial-gradient(ellipse at 25% 20%, #2b245b, #111329 60%, #080910)', color: 'white' }}>
        {!active ? null : untimed
            ? <div style={{ position: 'absolute', inset: '80px 24px 130px', overflowY: 'auto', whiteSpace: 'pre-wrap', lineHeight: 2.1, textAlign: 'center', fontSize: 23 }}>{metadata.text}</div>
            : <Visualizer key={metadata.id} currentTime={clock} currentLineIndex={lineIndex}
                lines={metadata.lines} theme={theme} audioPower={zero} audioBands={bands}
                songTitle={metadata.title} songArtist={metadata.artist} seed={metadata.id}
                isPreviewMode={true} paused={paused} backgroundStaticMode={true}
                lyricsFontScale={0.75} subtitleFontScale={0.85} showText={metadata.lines.length > 0}
                onLyricLineSeek={time => window.webkit?.messageHandlers.folia.postMessage({ type: 'seek', time, id: metadata.id })}
            />}
    </div>;
}
createRoot(document.getElementById('root')!).render(<LyricPage />);
