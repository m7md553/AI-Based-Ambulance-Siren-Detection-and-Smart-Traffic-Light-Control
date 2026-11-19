
function emergencyTrafficControl(sirenDetected)
% التحكم في إشارة المرور حسب اكتشاف سرينة الإسعاف

if sirenDetected >= 1
    % Emergency mode
    updateSumoStep(0, 0, 1);
else
    % Normal mode
    updateSumoStep(1, 0, 0);
end

end
