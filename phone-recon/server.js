require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const twilio = require('twilio');

const app = express();
app.use(cors());
app.use(express.json());

const twilioClient = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

function requireSecret(req, res, next) {
  const key = req.headers['x-api-secret'];
  if (!key || key !== process.env.API_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// Normalize to E.164 — strips spaces/dashes, prepends +1 if bare 10-digit US number
function normalizeNumber(raw) {
  const digits = raw.replace(/\D/g, '');
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  return `+${digits}`;
}

async function lookupTwilio(e164) {
  try {
    const result = await twilioClient.lookups.v2
      .phoneNumbers(e164)
      .fetch({ fields: 'line_type_intelligence,caller_name' });

    return {
      valid: result.valid,
      countryCode: result.countryCode,
      nationalFormat: result.nationalFormat,
      lineType: result.lineTypeIntelligence?.type ?? null,
      lineTypeConfidence: result.lineTypeIntelligence?.errorCode === null
        ? 'high'
        : 'low',
      callerName: result.callerName?.callerName ?? null,
      callerType: result.callerName?.callerType ?? null,
      carrier: result.lineTypeIntelligence?.carrierName ?? null,
    };
  } catch (err) {
    return { error: err.message };
  }
}

async function lookupNumLookup(e164) {
  try {
    const { data } = await axios.get('https://api.numlookupapi.com/v1/info/' + encodeURIComponent(e164), {
      params: { apikey: process.env.NUMLOOKUP_API_KEY },
      timeout: 8000,
    });
    return {
      valid: data.valid,
      country: data.country_name,
      countryCode: data.country_code,
      location: data.location,
      carrier: data.carrier,
      lineType: data.line_type,
      localFormat: data.local_format,
      intlFormat: data.international_format,
    };
  } catch (err) {
    return { error: err.message };
  }
}

async function lookupHIBP(e164) {
  try {
    // HIBP phone lookup uses the raw number without +
    const phone = e164.replace('+', '');
    const { data } = await axios.get(
      `https://haveibeenpwned.com/api/v3/breachedaccount/${encodeURIComponent(e164)}`,
      {
        headers: {
          'hibp-api-key': process.env.HIBP_API_KEY,
          'user-agent': 'PhoneRecon/1.0',
        },
        params: { truncateResponse: false },
        timeout: 8000,
      }
    );
    return {
      breached: true,
      breachCount: data.length,
      breaches: data.map(b => ({
        name: b.Name,
        domain: b.Domain,
        breachDate: b.BreachDate,
        dataClasses: b.DataClasses,
        description: b.Description,
      })),
    };
  } catch (err) {
    if (err.response?.status === 404) return { breached: false, breachCount: 0, breaches: [] };
    return { error: err.message };
  }
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', ts: new Date().toISOString() });
});

app.post('/lookup', requireSecret, async (req, res) => {
  const { number } = req.body;
  if (!number || typeof number !== 'string') {
    return res.status(400).json({ error: 'number is required' });
  }

  const e164 = normalizeNumber(number.trim());

  // Fire all three in parallel — don't let one slow API block the others
  const [twilio, numLookup, hibp] = await Promise.all([
    lookupTwilio(e164),
    lookupNumLookup(e164),
    lookupHIBP(e164),
  ]);

  res.json({
    query: number,
    e164,
    timestamp: new Date().toISOString(),
    twilio,
    numLookup,
    hibp,
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`PhoneRecon server running on port ${PORT}`);
});
