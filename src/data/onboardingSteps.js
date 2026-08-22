export const ONBOARDING_STEPS = ['welcome', 'license', 'privacy', 'library'];

export function canAdvance(step, state) {
  switch (step) {
    case 'license': return state.licenseAgreed === true;
    case 'library': return !!state.libraryPath;
    default: return true;
  }
}

export function nextStep(step) {
  const i = ONBOARDING_STEPS.indexOf(step);
  return i >= 0 && i < ONBOARDING_STEPS.length - 1 ? ONBOARDING_STEPS[i + 1] : null;
}

export function prevStep(step) {
  const i = ONBOARDING_STEPS.indexOf(step);
  return i > 0 ? ONBOARDING_STEPS[i - 1] : null;
}
