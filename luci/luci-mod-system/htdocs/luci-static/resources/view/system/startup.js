'use strict';
'require view';
'require rpc';
'require fs';
'require ui';

var isReadonlyView = !L.hasViewPermission() || null;

return view.extend({
	load: function () {
		return Promise.all(
			[
				L.resolveDefault(fs.read('/etc/crontabs/root'), ''),
				L.resolveDefault(fs.read('/etc/rc.local'), '')
			]
		)
	},

	handleRcLocalSave: function (ev) {
		var rcLocal = (document.querySelector('.rclocal').value || '').trim().replace(/\r\n/g, '\n') + '\n';
		var crontab = (document.querySelector('.crontab').value || '').trim().replace(/\r\n/g, '\n') + '\n';

		return fs.write('/etc/rc.local', rcLocal)
			.then(fs.write('/etc/crontabs/root', crontab))
			.then(function () {
				document.querySelector('.rclocal').value = rcLocal;
				document.querySelector('.crontab').value = crontab;
				ui.addNotification(null, E('p', _('Contents have been saved.')), 'info');
			})
			.catch(function (e) {
				ui.addNotification(null, E('p', _('Unable to save contents: %s').format(e.message)));
			});
	},


	render: function (data) {
		var rcLocal = data[1],
			crontab = data[0]

		var view = E('div', {}, [
			E('h2', _('Scheduled Tasks / Startup')),
			E('div', {}, [
				E('div', { 'data-tab': 'init', 'data-tab-title': _('Scheduled Tasks') }, [
					E('p', { 'class': 'cbi-section-descr' }, _('This is the system crontab in which scheduled tasks can be defined.')),
					E('p', {}, E('textarea', { 'class': 'crontab', 'style': 'width:100%', 'rows': 25, 'disabled': isReadonlyView }, [crontab != null ? crontab : ''])),
					E('div', { 'class': 'cbi-page-actions' }, [
						E('button', {
							'class': 'btn cbi-button-save',
							'click': ui.createHandlerFn(this, 'handleRcLocalSave'),
							'disabled': isReadonlyView
						}, _('Save'))
					])
				]),
				E('div', { 'data-tab': 'rc', 'data-tab-title': _('Local Startup') }, [
					E('p', {}, _('This is the content of /etc/rc.local. Insert your own commands here (in front of \'exit 0\') to execute them at the end of the boot process.')),
					E('p', {}, E('textarea', { 'class': 'rclocal', 'style': 'width:100%', 'rows': 20, 'disabled': isReadonlyView }, [(rcLocal != null ? rcLocal : '')])),
					E('div', { 'class': 'cbi-page-actions' }, [
						E('button', {
							'class': 'btn cbi-button-save',
							'click': ui.createHandlerFn(this, 'handleRcLocalSave'),
							'disabled': isReadonlyView
						}, _('Save'))
					])
				])
			])
		]);

		ui.tabs.initTabGroup(view.lastElementChild.childNodes);

		return view;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});