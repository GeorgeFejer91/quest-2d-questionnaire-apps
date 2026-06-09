// Rename the package below to your Unity Android package before compiling.
package org.example.mystimulus;

import android.content.Intent;

import com.unity3d.player.UnityPlayerGameActivity;

public class QuestQuestionnaireUnityActivity extends UnityPlayerGameActivity {
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
    }
}
