export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'perf', 'refactor', 'style', 'docs', 'test', 'chore', 'ci', 'build', 'revert'],
    ],
    // Dependabot commit bodies include long markdown URLs (changelog /
    // compare links) that can exceed the conventional default of 100.
    'body-max-line-length': [2, 'always', 200],
  },
};
