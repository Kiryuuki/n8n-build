console.log("=========================================");
console.log("EXT-HOOK: STARTING LOAD...");
console.log("=========================================");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

module.exports = {
  n8n: {
    ready: [
      async function() {
        console.log("[HOOK] n8n IS READY AND HOOKS ARE ACTIVE");
        console.log("[HOOK] URL Check:", SUPABASE_URL ? "OK" : "MISSING");
      },
    ],
  },
  workflow: {
    postExecute: [
      async function(fullRunData, workflowData, executionId) {
        console.log(`[HOOK] WORKFLOW FINISHED: ${workflowData.name}`);
        
        const logData = {
          execution_id: executionId,
          workflow_name: workflowData.name,
          status: fullRunData.status,
        };

        if (!SUPABASE_URL) {
           console.log("[HOOK] Skipping Supabase - No URL");
           return;
        }

        try {
          await fetch(`${SUPABASE_URL}/rest/v1/n8n_execution_logs`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "apikey": SUPABASE_SERVICE_KEY,
              "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
            },
            body: JSON.stringify(logData),
          });
          console.log("[HOOK] SUCCESS: Data sent to Supabase");
        } catch (e) {
          console.log("[HOOK] FETCH ERROR:", e.message);
        }
      },
    ],
  },
};