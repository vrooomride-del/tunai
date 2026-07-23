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
일반 소비자용 앱이므로 각 밴드마다 "왜 이 보정을 했는지"를 한 문장으로 reason에 담아 사용자를 이해시켜야 합니다.
soundScore는 튜닝 후 예상 음질 점수(0-100, 정수)로, 검출된 공진 문제가 얼마나 심각했는지와
이번 보정으로 얼마나 개선됐는지를 종합해 산정합니다.
규칙: frequency(Hz 정수), gainDb(음수 -1~-24), q(1~10), enabled(true), reason(한국어 한 문장, 예: "책상 반사 180Hz 보정")
JSON 형식 외 출력 금지.
출력: {"soundScore":89,"bands":[{"frequency":120,"gainDb":-3.5,"q":4.0,"enabled":true,"reason":"책상 반사로 인한 피크 보정"}],"explanation":"한국어 2-3문장"}`;

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
      return { bands: json.bands, explanation: json.explanation, soundScore: json.soundScore };
    } catch (e) {
      if (e.status === 429) throw new HttpsError('resource-exhausted', 'AI 사용량 한도 초과.');
      throw new HttpsError('internal', `AI 오류: ${e.message}`);
    }
  }
);

// ── TUNAI Acoustic Intelligence Layer (Consumer) ────────────────
// Interpretation ONLY. The model never sees a dB/Hz/Q value and never returns
// a DSP band — the deterministic on-device engine owns every correction. This
// receives coarse, engineering-term-free descriptors (which regions were
// reduced/lifted, capture confidence, placement) and returns consumer-language
// prose. See lib/core/acoustic_analysis.dart (AcousticAnalysisDigest).
const SYSTEM_ANALYZE_KO = `당신은 하이엔드 오디오 시스템의 음향 컨설턴트입니다.
사용자가 이해하기 쉬운 언어로 공간과 스피커의 관계, 적용된 변화, 그리고 설치 환경 개선 방법을 설명합니다.
당신은 DSP 엔지니어가 아닙니다. 필터 값이나 기술 수치를 생성하지 않습니다.
측정 결과와 실제 적용된 분석 정보만 사용합니다.
절대 규칙:
- dB, Hz, Q, PEQ, EQ, DSP, 필터, 게인, 주파수, 밴드 같은 기술 용어와 숫자 수치를 절대 쓰지 않습니다.
- 주어진 correction 정보에 없는 개선 효과를 지어내거나 과장하지 않습니다.
- 주어진 정보에 근거해서만 말합니다.
입력 필드: corrections(region=low/mid/high, direction=reduced/lifted), confidence(stable/moderate/low), placement.
출력은 JSON만: {"summary":"한 문장","changes":["짧은 문구", ...],"placementAdvice":"한 문장 또는 생략","listeningAdvice":"한 문장 또는 생략","confidenceExplanation":"한 문장 또는 생략"}
- summary: 무엇을 조정했는지 한 문장. 예 "공간의 저역 균형을 조정했습니다."
- changes: 각 correction을 짧은 소비자 문구로. 예 "저음 울림을 줄였습니다"
- placementAdvice: placement_note가 주어졌을 때만, 그 내용에 근거해 실제 상황에 맞는 배치 조언 한두 문장. placement_note를 넘어서는 추측 금지. placement/placement_note가 없으면 이 필드를 생략.
- listeningAdvice: 어떤 청취 경험을 기대할 수 있는지 한 문장. 예 "보다 균형 잡힌 소리를 경험할 수 있습니다". 근거가 약하면 생략.
- confidenceExplanation: confidence가 stable이면 "측정이 안정적입니다" 류, low면 다시 측정 권유. 애매하면 생략.
근거가 없는 필드는 넣지 마세요.`;
const SYSTEM_ANALYZE_EN = `You are an acoustic consultant for a high-end audio system.
You do NOT design DSP values. Describe an already-completed automatic room sound optimization
in warm, concise, non-technical English for a listener who knows nothing about audio, and
guide them on placement and the listening experience.
Hard rules:
- Never use dB, Hz, Q, PEQ, EQ, DSP, filter, gain, frequency, band, or any engineering term or number.
- Never invent or overstate improvements beyond the given correction info.
- Speak only from the given information.
Input: corrections(region=low/mid/high, direction=reduced/lifted), confidence(stable/moderate/low), placement, placement_note.
Output JSON only: {"summary":"one sentence","changes":["short phrase", ...],"placementAdvice":"one sentence or omit","listeningAdvice":"one sentence or omit","confidenceExplanation":"one sentence or omit"}
- placementAdvice: only when a placement_note is given; base it on that note and never guess beyond it. Omit when there is no placement_note.
Omit any field you have no basis for.`;

exports.aiAnalyze = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const rateKey = request.auth?.uid || request.rawRequest?.ip || 'anonymous';
    if (!checkRateLimit(rateKey)) {
      throw new HttpsError('resource-exhausted', 'AI 한도를 초과했습니다.');
    }
    const { corrections, confidence, placement, locale } = request.data || {};
    // Real content required — never narrate an empty correction.
    if (!Array.isArray(corrections) || corrections.length === 0) {
      throw new HttpsError('invalid-argument', 'corrections가 필요합니다.');
    }
    const ko = locale !== 'en';
    const regionWord = { low: ko ? '저음' : 'low', mid: ko ? '중음' : 'mid', high: ko ? '고음' : 'high' };
    const dirWord = {
      reduced: ko ? '정리' : 'reduced',
      lifted: ko ? '보강' : 'lifted',
    };
    const corrStr = corrections
      .map((c) => `${regionWord[c.region] || c.region} ${dirWord[c.direction] || c.direction}`)
      .join(', ');
    // Factual acoustic context per placement — NOT invented, these are
    // well-established properties of the placement the user actually chose.
    // The model turns the relevant note into one grounded piece of advice;
    // it must never contradict or exceed it, and gets nothing when placement
    // is absent (no advice fabricated from thin air).
    const placementNote = {
      desk: ko
        ? '책상/근접 배치: 책상 표면과 벽 등 가까운 반사면의 영향이 커지기 쉬움. 스피커와 벽 사이 여유를 두면 도움.'
        : 'Desktop/near-field: nearby reflective surfaces (desk, wall) have more influence. Leaving space to the wall helps.',
      near_wall: ko
        ? '벽 근접 배치: 저역 에너지가 증가하기 쉬움. 벽에서 조금 띄우면 저음이 더 정돈됨.'
        : 'Near a wall: low-frequency energy tends to build up. A little distance from the wall tightens the bass.',
      living_room: ko
        ? '거실/넓은 공간: 넓은 공간과 벽 반사가 공간감에 영향. 청취 위치와 스피커 간 대칭이 도움.'
        : 'Living room/open space: room size and wall reflections shape spaciousness. A symmetric listening triangle helps.',
      studio: ko
        ? '스튜디오/모니터링: 이미 통제된 환경. 미세한 좌우 대칭과 청취 거리 조정 정도가 도움.'
        : 'Studio/monitoring: already a controlled space. Fine left/right symmetry and listening distance are what remain.',
    };
    const note = placement ? placementNote[placement] : undefined;
    const placeStr = placement
      ? `\nplacement: ${placement}${note ? `\nplacement_note: ${note}` : ''}`
      : '';
    const prompt = `corrections: ${corrStr}\nconfidence: ${confidence || 'unknown'}${placeStr}`;
    try {
      const json = await callGemini(prompt, ko ? SYSTEM_ANALYZE_KO : SYSTEM_ANALYZE_EN);
      // Pass through only the known shape; drop anything unexpected.
      const out = {};
      if (typeof json.summary === 'string') out.summary = json.summary;
      const rawChanges = Array.isArray(json.changes) ? json.changes : json.improvements;
      if (Array.isArray(rawChanges)) {
        out.changes = rawChanges.filter((s) => typeof s === 'string');
      }
      if (typeof json.placementAdvice === 'string') out.placementAdvice = json.placementAdvice;
      if (typeof json.listeningAdvice === 'string') out.listeningAdvice = json.listeningAdvice;
      if (typeof json.confidenceExplanation === 'string') out.confidenceExplanation = json.confidenceExplanation;
      return out;
    } catch (e) {
      if (e.status === 429) throw new HttpsError('resource-exhausted', 'AI 사용량 한도 초과.');
      throw new HttpsError('internal', `AI 오류: ${e.message}`);
    }
  }
);

// ── TUNAI User Intent Layer (Consumer) ──────────────────────────
// Translates a user's plain-language listening request into a STRUCTURED
// PERCEPTUAL intent. It never designs a correction and never emits a DSP
// value — the on-device engine owns all numbers. The client additionally
// rejects any response carrying an engineering field (see AcousticIntent.of).
const SYSTEM_INTENT = `You translate a listener's plain-language request into a structured PERCEPTUAL intent.
You are NOT a DSP engineer. You NEVER output frequency, gain, Q, filter, PEQ, EQ, crossover, dB, Hz,
register, band, or any numeric tuning value. Output perceptual categories only.
Output JSON only with ONLY these keys (omit any you cannot infer):
{"soundCharacter":"natural|warm|detailed|energetic|relaxed","bassPreference":"controlled|natural|powerful","vocalPreference":"natural|forward","listeningGoal":"music|movie|desktop|longListening","listeningFatigue":"low|moderate|high","confidence":"low|medium|high"}
Rules:
- Use ONLY the allowed values above. Never invent a value.
- Infer only what the request actually implies; omit anything it does not.
- "오래 들어도 편안한" / "easy for long sessions" => listeningFatigue:"low", often listeningGoal:"longListening".
- confidence reflects how clearly the request maps to these categories.
- Never include any key other than the six above.`;

exports.aiIntent = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const rateKey = request.auth?.uid || request.rawRequest?.ip || 'anonymous';
    if (!checkRateLimit(rateKey)) {
      throw new HttpsError('resource-exhausted', 'AI 한도를 초과했습니다.');
    }
    const { userRequest } = request.data || {};
    if (typeof userRequest !== 'string' || !userRequest.trim()) {
      throw new HttpsError('invalid-argument', 'userRequest가 필요합니다.');
    }
    const prompt = `Listener request: "${userRequest.trim()}"`;
    try {
      const json = await callGemini(prompt, SYSTEM_INTENT);
      // Whitelist the allowed keys/values; drop everything else. This is a
      // second guard on top of the client's forbidden-field rejection.
      const allowed = {
        soundCharacter: ['natural', 'warm', 'detailed', 'energetic', 'relaxed'],
        bassPreference: ['controlled', 'natural', 'powerful'],
        vocalPreference: ['natural', 'forward'],
        listeningGoal: ['music', 'movie', 'desktop', 'longListening'],
        listeningFatigue: ['low', 'moderate', 'high'],
        confidence: ['low', 'medium', 'high'],
      };
      const out = {};
      for (const [key, values] of Object.entries(allowed)) {
        if (typeof json[key] === 'string' && values.includes(json[key])) {
          out[key] = json[key];
        }
      }
      return out;
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
