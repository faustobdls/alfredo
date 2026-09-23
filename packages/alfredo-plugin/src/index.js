export default class AlfredoPlugin {
  constructor(ctx, config) {
    this.ctx = ctx;
    this.config = config;
    ctx.on('ready', () => {
      console.log('Alfredo Plugin is ready');
    });
  }
}
AlfredoPlugin.inject = ['ctx'];
