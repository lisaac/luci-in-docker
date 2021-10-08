'use strict';
'require ui';
'require view';
'require dom';
'require poll';
'require uci';
'require rpc';
'require fs';
'require form';
let result

const PLUGIN_DIR = '/external/plugin/'

const renderMoreOptionsModal = function (section_id, ev) {
	var parent = this.map,
		title = parent.title,
		name = null,
		m = new form.JSONMap({}, null, null),
		s = m.section(form.NamedSection, section_id, this.sectiontype);
	m.parent = parent
	m.data = parent.data
	m.readonly = parent.readonly

	s.tabs = this.tabs;
	s.tab_names = this.tab_names;
	s.parentmap = parent;

	if ((name = this.titleFn('modaltitle', section_id)) != null)
		title = name;
	else if ((name = this.titleFn('sectiontitle', section_id)) != null)
		title = '%s - %s'.format(parent.title, name);
	else if (!this.anonymous)
		title = '%s - %s'.format(parent.title, section_id);

	for (var i = 0; i < this.children.length; i++) {
		var o1 = this.children[i];

		if (o1.modalonly === false)
			continue;

		var o2 = s.option(o1.constructor, o1.option, o1.title, o1.description);

		for (var k in o1) {
			if (!o1.hasOwnProperty(k))
				continue;

			switch (k) {
				case 'map':
				case 'section':
				case 'option':
				case 'title':
				case 'description':
					continue;

				default:
					o2[k] = o1[k];
			}
		}
	}

	return Promise.resolve(this.addModalOptions(s, section_id, ev)).then(L.bind(m.render, m)).then(L.bind(function (nodes) {
		ui.showModal(title, [
			nodes,
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.createHandlerFn(this, 'handleModalCancel', m, section_id)
				}, [_('Dismiss')]), ' ',
				E('button', {
					'class': 'cbi-button cbi-button-positive important',
					'click': ui.createHandlerFn(this, 'handleModalSave', m, section_id),
					'disabled': m.readonly || null
				}, [_('Add')])
			])
		], 'cbi-modal');
	}, this)).catch(L.error);
}

const rename = function (oldName, newName) {
	let callFileExec = rpc.declare({
		object: 'file',
		method: 'exec',
		params: ['command', 'params', 'env']
	});
	return callFileExec("mkdir -p ".concat(newName.substring(0, newName.lastIndexOf('/'))))
		.then(callFileExec("mv ".concat(oldName).concat(" ").concat(newName)))
}

const renamePlugin = function (section_id) {
	ui.showModal(_('Rename Plugin:'), [
		E('p', {}, [E('em', { 'style': 'white-space:pre' }, result[section_id].name)]),
		E('input', { type: 'text', 'class': 'cbi-section-create-name rename-text', value: result[section_id].name }),
		E('div', { 'class': 'right' }, [
			E('button', {
				'class': 'cbi-button',
				'click': (() => {
					ui.hideModal()
				})
			}, [_('Dismiss')]),
			E('button', {
				'class': 'cbi-button cbi-button-positive important',
				'click': (() => {
					const newName = document.querySelector('.rename-text').value
					if (newName != result[section_id].name) {
						rename(PLUGIN_DIR + result[section_id].name, PLUGIN_DIR + newName)
							.then(location.reload())
					}
					ui.hideModal()
				})
			}, [_('Save')])
		])
	], 'cbi-modal')
}

const newPlugin = function (ev, name) {
	var config_name = this.uciconfig || this.map.config,
		section_id = this.map.data.add(config_name, this.sectiontype, name, 0);

	this.addedSection = section_id;
	this.renderMoreOptionsModal(section_id)
}

const enablePlugin = function (section_id) {
	if (result[section_id].enabled) {
		let newName = PLUGIN_DIR + result[section_id].name
		let l = newName.lastIndexOf('/') + 1
		newName = newName.slice(0, l) + "_" + newName.slice(l);
		rename(PLUGIN_DIR + result[section_id].name, newName)
			.then(location.reload())
	}
	else {
		let d = result[section_id].name.split('/')
		let newName = ""
		d.forEach(e => {
			if (e.match(/^_/)) {
				newName = newName + '/' + e.slice(1)
			}
			else {
				newName = newName + '/' + e
			}
		})
		newName = PLUGIN_DIR + newName
		rename(PLUGIN_DIR + result[section_id].name, newName)
			.then(location.reload())
	}
}

const removePlugin = function (section_id) {
	fs.exec_direct("rm", ['-fr', PLUGIN_DIR + result[section_id].name]).then(() => {
		delete result[section_id]
		this.map.render()
	})
}
return view.extend({
	load: function () {
		const plugin = {}
		return fs.exec_direct("/usr/bin/find", [PLUGIN_DIR, '-iname', 'Makefile', '-type', 'f'])
	},
	render: function (data) {
		var m, s, o, ss, so
		const P = { plugins: [] }
		let index = 0
		data.split('\n').sort().forEach(e => {
			if (e == "") return
			let x = e.substring(0, e.indexOf('/Makefile'))
			x = x.substring(17)
			let disabled = e.match(/\/\_/)
			if (!disabled) {
				index += 1
			}
			P.plugins.push({
				index: disabled ? null : index,
				name: x,
				enabled: disabled ? false : true
			})
		});

		m = new form.JSONMap(P, _('Plugins'));
		result = m.data.data
		s = m.section(form.GridSection, "plugins")
		s.anonymous = true
		o = s.option(form.DummyValue, "index", _("Merge Priority"))
		o = s.option(form.DummyValue, "name", _("Plugin"))
		s.renamePlugin = renamePlugin
		s.removePlugin = removePlugin
		s.newPlugin = newPlugin
		s.enablePlugin = enablePlugin
		s.renderMoreOptionsModal = renderMoreOptionsModal
		s.renderSectionAdd = function (extra_class) {

			var createEl = E('div', { 'class': 'cbi-section-create' }),
				btn_title = this.titleFn('addbtntitle');

			if (extra_class != null)
				createEl.classList.add(extra_class);
			dom.append(createEl, [
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'title': _('Add'),
					'click': ui.createHandlerFn(this, 'newPlugin', null),
				}, [_('Add')])
			])

			return createEl;
		}
		s.renderRowActions = function (section_id) {
			var tdEl = this.super('renderRowActions', [section_id, _('Edit')])

			dom.content(tdEl.lastChild, [
				E('button', {
					'class': result[section_id].enabled ? 'cbi-button cbi-button-negative' : 'cbi-button cbi-button-positive',
					'click': ui.createHandlerFn(this, 'enablePlugin', section_id),
					'title': result[section_id].enabled ? _('Disable') : _('Enable')
				}, result[section_id].enabled ? _('Disable') : _('Enable')),
				E('button', {
					'class': 'cbi-button cbi-button-edit',
					'click': ui.createHandlerFn(this, 'renamePlugin', section_id),
					'title': _('Rename')
				}, _('Rename')),
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, 'removePlugin', section_id),
					'title': _('Remove'),
					'disabled': result[section_id].enabled ? true : null
				}, _('Remove'))
			]);
			return tdEl;
		};
		s.addModalOptions = function (ss, sidConfig, ev) {
			ss.tab('repo', _('Repo'));
			ss.tab('zip', _('ZIP'));
			o = ss.taboption('repo', form.Value, 'repo', _("Plugin Repo"))
			o.placeholder = 'https://github.com/lisaac/luci-app-dockerman'
			o.width = 1000
			o.value("https://github.com/lisaac/luci-app-diskman", _("Diskman"))
			o.value("https://github.com/lisaac/luci-app-dockerman", _("Dockerman"))
			o.write = function (sid, value) {
				if (value.match(/(ht|f)tp(s?)\:\/\/[0-9a-zA-Z]([-.\w]*[0-9a-zA-Z])*(:(0-9)*)*(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&amp;%$#_]*)?/)) {
					const pluginName = value.substring(value.lastIndexOf('/') + 1)
					if (!pluginName || pluginName == '') {
						ui.hideModal()
						return
					}
					for (var x in result) {
						let re = new RegExp(pluginName + '$')
						if (result[x].name && result[x].name.match(re)) {
							setTimeout(() => {
								ui.hideModal()
							}, 0);
							ui.addNotification(null, E('p', _('Plugin') + ': ' + pluginName + ' ' + _('already exist!!')), 'danger');
							return
						}
					}
					fs.exec("git", ['clone', '--depth=1', value, PLUGIN_DIR + pluginName])
						.then(() => {
							ui.hideModal()
							location.reload()
						})
						.catch(e => {
							ui.addNotification(null, E('p', _('Failed to clone plugin') + ' ' + value), 'danger');
							ui.hideModal()
						})
				} else {
					ui.hideModal()
				}

			}
			// o = ss.taboption('zip', form.FileUpload, 'zip', _("Plugin ZIP"))
		}
		s.handleModalSave = function (modalMap, sid, ev) {
			return modalMap.save(() => {
				ui.showModal(_('New Plugin'), [
					E('p', { 'class': 'spinning' }, _('Cloning new plugin ...'))
				]);
			}, false)
				// .then(L.bind(this.map.load, this.map))
				// .then(L.bind(this.map.reset, this.map))
				.then(ui.hideModal)
				.catch(function () { });
		}
		return m.render()

	},
	handleSaveApply: null,
	handleReset: null,
	handleSave: null
})