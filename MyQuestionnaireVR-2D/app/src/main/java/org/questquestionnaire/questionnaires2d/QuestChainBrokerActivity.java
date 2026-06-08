package org.questquestionnaire.questionnaires2d;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

public final class QuestChainBrokerActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        handleBrokerIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleBrokerIntent(intent);
    }

    private void handleBrokerIntent(Intent intent) {
        try {
            QuestChainBroker.Result result = QuestChainBroker.handle(this, intent);
            if (result.outgoingIntent != null) {
                startActivity(result.outgoingIntent);
            }
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_BROKER status=" + result.status
                + " outgoing=" + (result.outgoingIntent != null ? result.outgoingIntent.getComponent() : "none"));
        } catch (Exception exception) {
            Log.e(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_BROKER_ERROR " + exception.getMessage(), exception);
        } finally {
            finish();
        }
    }
}
