console.log("=========================================");
console.log("EXT-HOOK: STARTING LOAD...");
console.log("=========================================");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

module.exports = {
  n8n: {
    ready: [
      async function () {
        console.log("[HOOK] n8n IS READY AND HOOKS ARE ACTIVE");
        console.log("[HOOK] URL Check:", SUPABASE_URL ? "OK" : "MISSING");
      },
    ],
  },
  workflow: {
    postExecute: [
      async function (fullRunData, workflowData, executionId) {
        console.log(`[HOOK] WORKFLOW FINISHED: ${workflowData.name}`);

        if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
          console.log("[HOOK] Skipping Supabase - missing env vars");
          return;
        }

        const logData = {
          execution_id: String(executionId),
          workflow_id: String(workflowData.id || ""),
          workflow_name: workflowData.name,
          status: fullRunData.status,
          started_at: fullRunData.startedAt || new Date().toISOString(),
          finished_at: fullRunData.stoppedAt || new Date().toISOString(),
        };

        try {
          const res = await fetch(
            `${SUPABASE_URL}/rest/v1/n8n_execution_logs`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                "Prefer": "return=minimal",
              },
              body: JSON.stringify(logData),
            }
          );

          if (!res.ok) {
            // Log full error so we can see exactly what Supabase rejected
            const body = await res.text();
            console.log(`[HOOK] SUPABASE ERROR ${res.status}: ${body}`);
          } else {
            console.log(`[HOOK] SUCCESS: logged execution ${executionId}`);
          }
        } catch (e) {
          console.log("[HOOK] FETCH ERROR:", e.message);
        }
      },
    ],
  },
};