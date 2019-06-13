import org.openqa.grid.internal.utils.DefaultCapabilityMatcher;

import java.util.Map;
 
public class EdgeCapabilityMatcher extends DefaultCapabilityMatcher {
    private final String edgeHtmlVersion = "edgeHtmlVersion";

    @Override
    public boolean matches(Map<String, Object> currentCapability, Map<String, Object> requestedCapability) {
        boolean basicChecks = super.matches(currentCapability, requestedCapability);

        if (! requestedCapability.containsKey(edgeHtmlVersion)) {
            return basicChecks;
        }

        if (! currentCapability.containsKey(edgeHtmlVersion)) {
            return basicChecks;
        }

        return (basicChecks && currentCapability.get(edgeHtmlVersion).toString().startsWith(requestedCapability.get(edgeHtmlVersion).toString()));
    }
}

