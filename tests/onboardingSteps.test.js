import { describe, it, expect } from 'vitest';
import { ONBOARDING_STEPS, canAdvance, nextStep, prevStep } from '../src/onboardingSteps';

describe('ONBOARDING_STEPS', () => {
  it('is exactly welcome → license → privacy → library', () => {
    expect(ONBOARDING_STEPS).toEqual(['welcome', 'license', 'privacy', 'library']);
  });
});

describe('canAdvance', () => {
  it('welcome and privacy always advance', () => {
    expect(canAdvance('welcome', {})).toBe(true);
    expect(canAdvance('privacy', {})).toBe(true);
  });
  it('license requires the agreement checkbox', () => {
    expect(canAdvance('license', { licenseAgreed: false })).toBe(false);
    expect(canAdvance('license', {})).toBe(false);
    expect(canAdvance('license', { licenseAgreed: true })).toBe(true);
  });
  it('library requires a chosen path', () => {
    expect(canAdvance('library', { libraryPath: '' })).toBe(false);
    expect(canAdvance('library', { libraryPath: '/Users/me/Music' })).toBe(true);
  });
});

describe('navigation', () => {
  it('nextStep walks forward and ends at null', () => {
    expect(nextStep('welcome')).toBe('license');
    expect(nextStep('license')).toBe('privacy');
    expect(nextStep('privacy')).toBe('library');
    expect(nextStep('library')).toBeNull();
  });
  it('prevStep walks backward and ends at null', () => {
    expect(prevStep('library')).toBe('privacy');
    expect(prevStep('privacy')).toBe('license');
    expect(prevStep('license')).toBe('welcome');
    expect(prevStep('welcome')).toBeNull();
  });
});
