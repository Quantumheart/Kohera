export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'perf', 'refactor', 'style', 'docs', 'test', 'chore', 'ci', 'build', 'revert'],
    ],
  },
};
