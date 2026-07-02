const { onCall, HttpsError, onRequest } = require('firebase-functions/v2/https');
const { GoogleGenAI } = require('@google/genai');

const callCounts = new Map();
const RATE_LIMIT = 20;
const RATE_WINDOW_MS = 3600000;

function checkRateLimit(key) {
  const now = Date.now();
  const entry = callCounts.get(key) || { count: 0, windowStart: now };
  if (now - entry.windowStart > RATE_WINDOW_MS) {
    callCounts.set(key, { count: 1, windowStart: now });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  callCounts.set(key, entry);
  return true;
}

function makeAI() {
  return new GoogleGenAI({
    vertexai: true,
    project: 'tunai-54b7f',
    location: 'us-central1',
  });
}

async function callGemini(prompt, systemInstruction) {
  const ai = makeAI();
  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash',
    contents: prompt,
    config: {
      systemInstruction,
      temperature: 0.1,
      responseMimeType: 'application/json',
    },
  });
  const text = typeof response.text === 'function' ? response.text() : response.text;
  return JSON.parse(text);
}

// ── TUNAI (mobile) ──────────────────────────────────────────────
const SYSTEM_MOBILE = `당신은 전문 DSP 음향 엔지니어입니다. ADAU1701/1466 DSP의 PEQ 노치 필터를 설계합니다.
규칙: frequency(Hz 정수), gainDb(음수 -1~-24), q(1~10), enabled(true)
JSON 형식 외 출력 금지.
출력: {"bands":[{"frequency":120,"gainDb":-3.5,"q":4.0,"enabled":true}],"explanation":"한국어 2-3문장"}`;

exports.aiTune = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const rateKey = request.auth?.uid || request.rawRequest?.ip || 'anonymous';
    if (!checkRateLimit(rateKey)) {
      throw new HttpsError('resource-exhausted', '시간당 AI 튜닝 한도를 초과했습니다.');
    }
    const { peaks, userRequest, speakerProfile, location } = request.data;
    if (!peaks || !Array.isArray(peaks) || peaks.length === 0) {
      throw new HttpsError('invalid-argument', 'peaks 데이터가 필요합니다.');
    }
    const peakStr = peaks.map((p, i) =>
      `Peak${i + 1}: ${Number(p.frequency).toFixed(0)}Hz, ${Number(p.gain).toFixed(1)}dB, Q${Number(p.q).toFixed(2)}`
    ).join('\n');
    let tsSection = '';
    if (speakerProfile) {
      tsSection = `\nSPEAKER T/S: Fs=${speakerProfile.fs}Hz, Xmax=${speakerProfile.xmax}mm, 감도=${speakerProfile.sensitivity}dB`;
    }
    const locationLabels = {
      desk: '책상 위 (근접 반사면 존재)',
      living_room: '거실 (넓은 공간, 벽 반사)',
      near_wall: '벽 근처 배치 (저역 부밍 가능)',
      studio: '스튜디오/모니터링 환경',
      custom: '사용자 지정 위치',
    };
    let locationSection = '';
    if (location) {
      locationSection = `\n설치 위치: ${locationLabels[location] || location} — 이 위치 특성을 감안해 튜닝하고, 위치 관련 보정이 있다면 explanation에 언급할 것`;
    }
    const prompt = `측정된 공진 주파수:\n${peakStr}${tsSection}${locationSection}\n사용자 요청: ${userRequest || '자연스럽고 균형잡힌 소리로 튜닝해줘'}`;
    try {
      const json = await callGemini(prompt, SYSTEM_MOBILE);
      return { bands: json.bands, explanation: json.explanation };
    } catch (e) {
      if (e.status === 429) throw new HttpsError('resource-exhausted', 'AI 사용량 한도 초과.');
      throw new HttpsError('internal', `AI 오류: ${e.message}`);
    }
  }
);

// ── TUNAI PRO (desktop) ─────────────────────────────────────────
const SYSTEM_PRO = `You are an expert audio DSP engineer specializing in active speaker systems.
Analyze DSP settings and provide PEQ adjustment recommendations.
Output ONLY valid JSON. No other text.
Format: {"analysis":"Korean 2-3 sentences","bands":[{"index":0,"frequency":80.0,"gainDb":-3.0,"q":2.0,"type":0,"enabled":true,"reason":"Korean reason"}],"summary":"Korean summary"}
Rules: type 0=peaking 1=lowShelf 2=highShelf 3=lowPass 4=highPass 5=notch, index 0-19, freq 20-20000Hz, gainDb -24~+24, q 0.1~16`;

exports.aiTunePro = onRequest(
  { region: 'asia-northeast3', timeoutSeconds: 60, memory: '256MiB',
    cors: ['app://-', 'http://localhost', 'https://localhost'] },
  async (req, res) => {
    if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

    const ip = req.headers['x-forwarded-for'] || req.ip || 'unknown';
    if (!checkRateLimit(ip)) {
      res.status(429).json({ error: '시간당 AI 튜닝 한도를 초과했습니다.' });
      return;
    }

    const { dspState, userRequest, speakerProfile, systemProfile, frequencyResponse } = req.body;
    if (!dspState) { res.status(400).json({ error: 'dspState 필요' }); return; }

    const outIdx = dspState.selectedOutput ?? 0;
    const out = dspState.outputs?.[outIdx] ?? {};

    const bandsStr = (out.bands ?? []).map((b, i) =>
      `  Band${i}: ${Number(b.frequency).toFixed(0)}Hz ${Number(b.gainDb).toFixed(1)}dB Q${Number(b.q).toFixed(2)} type=${b.type} enabled=${b.enabled}`
    ).join('\n');

    const hp = out.hpFilter ? `HP: ${out.hpFilter.type} ${Number(out.hpFilter.frequency).toFixed(0)}Hz` : 'HP: BYPASS';
    const lp = out.lpFilter ? `LP: ${out.lpFilter.type} ${Number(out.lpFilter.frequency).toFixed(0)}Hz` : 'LP: BYPASS';

    let freqSection = '';
    if (frequencyResponse?.length) {
      const pts = frequencyResponse.slice(0, 30).map(r =>
        `${Number(r.frequency ?? r.f).toFixed(0)}Hz:${Number(r.db).toFixed(1)}dB`
      ).join(' ');
      freqSection = `\nMEASURED RESPONSE: ${pts}`;
    }

    let tsSection = '';
    if (speakerProfile) {
      tsSection = `\nSPEAKER: Fs=${speakerProfile.fs}Hz Xmax=${speakerProfile.xmax}mm Sens=${speakerProfile.sensitivity}dB`;
    }

    let sysSection = '';
    if (systemProfile) {
      sysSection = `\nSYSTEM: ${systemProfile.displayName} (${systemProfile.chipLabel})\nCH${outIdx}: ${systemProfile.channels?.[outIdx]?.name ?? out.name}`;
    }

    const prompt = `CHANNEL: ${out.name ?? `Ch${outIdx}`}
CROSSOVER: ${hp} | ${lp}
GAIN: ${Number(out.gainDb ?? 0).toFixed(1)}dB  DELAY: ${Number(out.delayMs ?? 0).toFixed(2)}ms
${sysSection}${tsSection}${freqSection}

CURRENT PEQ (20 bands):
${bandsStr}

USER REQUEST: "${userRequest || '자연스럽고 균형잡힌 소리로 튜닝해줘'}"`;

    try {
      const json = await callGemini(prompt, SYSTEM_PRO);
      res.json({ result: json });
    } catch (e) {
      console.error('[PRO AI]', e.message);
      res.status(500).json({ error: `AI 오류: ${e.message}` });
    }
  }
);
