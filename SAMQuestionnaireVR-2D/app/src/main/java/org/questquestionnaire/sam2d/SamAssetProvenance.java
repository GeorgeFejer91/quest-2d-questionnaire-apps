package org.questquestionnaire.sam2d;

import android.content.Context;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

final class SamAssetProvenance {
    String sourceRepository = "https://github.com/hexa-/SAM-vectors";
    String sourceLicense = "CC0-1.0";
    String sourceReference = "Lang, P. J. (1980). Behavioral treatment and bio-behavioral assessment: computer applications.";
    String valenceGridSha256 = "";
    String arousalGridSha256 = "";

    static SamAssetProvenance load(Context context) {
        SamAssetProvenance provenance = new SamAssetProvenance();
        try {
            String text = readAsset(context, "sam/asset-provenance.json");
            JSONObject json = new JSONObject(text);
            provenance.sourceRepository = json.optString("sourceRepository", provenance.sourceRepository);
            provenance.sourceLicense = json.optString("sourceLicense", provenance.sourceLicense);
            provenance.sourceReference = json.optString("sourceReference", provenance.sourceReference);
            JSONObject grids = json.optJSONObject("composedGrids");
            if (grids != null) {
                JSONObject valence = grids.optJSONObject("valence");
                JSONObject arousal = grids.optJSONObject("arousal");
                if (valence != null) {
                    provenance.valenceGridSha256 = valence.optString("sha256", "");
                }
                if (arousal != null) {
                    provenance.arousalGridSha256 = arousal.optString("sha256", "");
                }
            }
        } catch (Exception ignored) {
        }
        return provenance;
    }

    private static String readAsset(Context context, String path) throws Exception {
        StringBuilder builder = new StringBuilder();
        try (InputStream input = context.getAssets().open(path);
             BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line).append('\n');
            }
        }
        return builder.toString();
    }
}
