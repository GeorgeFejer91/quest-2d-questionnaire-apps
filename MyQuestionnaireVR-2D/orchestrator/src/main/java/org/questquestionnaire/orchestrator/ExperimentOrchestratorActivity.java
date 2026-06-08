package org.questquestionnaire.orchestrator;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;

public final class ExperimentOrchestratorActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        showStatus("Experiment orchestrator ready");
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        try {
            ExperimentOrchestratorBroker.Result result = ExperimentOrchestratorBroker.handle(this, intent);
            if (result.outgoingIntent != null) {
                startActivity(result.outgoingIntent);
            }
            showStatus("Orchestrator: " + result.status);
            Log.i(ExperimentOrchestratorBroker.TAG, "ORCHESTRATOR status=" + result.status
                + " outgoing=" + (result.outgoingIntent != null ? result.outgoingIntent.getComponent() : "none"));
        } catch (Exception exception) {
            showStatus("Orchestrator error");
            Log.e(ExperimentOrchestratorBroker.TAG, "ORCHESTRATOR_ERROR " + exception.getMessage(), exception);
        } finally {
            finish();
        }
    }

    private void showStatus(String text) {
        TextView view = new TextView(this);
        view.setGravity(Gravity.CENTER);
        view.setText(text);
        view.setTextSize(20f);
        setContentView(view);
    }
}
