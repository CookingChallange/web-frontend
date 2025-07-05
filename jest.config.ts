import type { Config } from 'jest';

const config: Config = {
	verbose: true,
	setupFilesAfterEnv: ['<rootDir>/src/setupTests.ts'],
	testEnvironment: 'jsdom',
  transform: {
    '^.+\\.tsx?$': 'ts-jest',
  },
};

export default config;

