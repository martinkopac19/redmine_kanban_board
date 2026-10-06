/* Kanban (Previo): pretiahnutie karty do iného stĺpca = zmena stavu úlohy.
   Karta sa presunie hneď; keď server zmenu odmietne (workflow, povinné pole, konflikt),
   vráti sa späť a ukáže sa dôvod. Presun do Blocked sa najprv opýta na (nepovinný) dôvod. */
(function () {
  function init() {
    var board = document.querySelector('.kb-board');
    if (!board || board.dataset.kbReady) return;
    board.dataset.kbReady = '1';
    var dragged = null, from = null, next = null;
    var flash = document.getElementById('kb-flash');
    var dialog = document.getElementById('kb-reason');

    function token() { var m = document.querySelector('meta[name="csrf-token"]'); return m ? m.content : ''; }
    function showError(msg) { if (!flash) return; flash.textContent = msg; flash.hidden = false; flash.scrollIntoView({ block: 'nearest' }); }
    function count(c) {
      var el = c.querySelector('.kb-col-count');
      if (el) el.textContent = c.querySelectorAll('.kb-card').length;
    }
    function recount() { board.querySelectorAll('.kb-col').forEach(count); }
    function col(el) { return el && el.closest ? el.closest('.kb-col') : null; }

    /* Dôvod blokovania je NEPOVINNÝ: Uložiť → text (aj prázdny), Zrušiť → Blocked bez dôvodu ('').
       null len pri krížiku / Esc — vtedy sa presun nekoná a karta sa vráti. */
    function askReason(card) {
      return new Promise(function (resolve) {
        var ta = dialog.querySelector('textarea');
        ta.value = card.dataset.reason || '';
        dialog.returnValue = '';
        dialog.addEventListener('close', function onClose() {
          dialog.removeEventListener('close', onClose);
          if (dialog.returnValue === 'ok') resolve(ta.value.trim());
          else if (dialog.returnValue === 'skip') resolve('');
          else resolve(null);
        });
        dialog.showModal();
        ta.focus();
      });
    }

    function revert(card, origin, before) {
      card.classList.remove('kb-saving');
      origin.querySelector('.kb-col-body').insertBefore(card, before && before.parentNode ? before : null);
      recount();
    }

    function move(card, target, origin, before) {
      var statusId = target.dataset.statusId;
      var toBlocked = board.dataset.blockedField === '1' && statusId === board.dataset.blockedStatus;
      // karta ide do cieľa hneď (vidno, kam padla); pri zrušení / chybe sa vráti
      target.querySelector('.kb-col-body').insertBefore(card, target.querySelector('.kb-card'));
      recount();
      var reasonP = toBlocked ? askReason(card) : Promise.resolve(undefined);
      reasonP.then(function (reason) {
        if (toBlocked && reason === null) { revert(card, origin, before); return; }
        card.classList.add('kb-saving');
        if (flash) flash.hidden = true;
        var body = new URLSearchParams();
        body.append('issue_id', card.dataset.issueId);
        body.append('status_id', statusId);
        body.append('global', board.dataset.global);
        if (reason !== undefined) body.append('blocked_reason', reason);
        fetch(board.dataset.moveUrl, {
          method: 'POST', credentials: 'same-origin', body: body,
          headers: { 'X-CSRF-Token': token(), 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
        }).then(function (r) {
          return r.json().catch(function () { return { error: r.status + ' ' + r.statusText }; })
            .then(function (j) { return { ok: r.ok, j: j }; });
        }).then(function (res) {
          if (!res.ok || !res.j.html) { revert(card, origin, before); showError(res.j.error || 'Error'); return; }
          var tmp = document.createElement('div');
          tmp.innerHTML = res.j.html.trim();
          card.parentNode.replaceChild(tmp.firstElementChild, card);
          recount();
        }).catch(function () { revert(card, origin, before); showError('Error'); });
      });
    }

    board.addEventListener('dragstart', function (e) {
      var card = e.target.closest && e.target.closest('.kb-card');
      if (!card) return;
      dragged = card; from = col(card); next = card.nextElementSibling;
      card.classList.add('kb-dragging');
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('text/plain', card.dataset.issueId);
    });
    board.addEventListener('dragend', function () {
      if (dragged) dragged.classList.remove('kb-dragging');
      board.querySelectorAll('.kb-over').forEach(function (c) { c.classList.remove('kb-over'); });
    });
    board.addEventListener('dragover', function (e) {
      var c = col(e.target);
      if (!dragged || !c) return;
      e.preventDefault();
      board.querySelectorAll('.kb-over').forEach(function (x) { if (x !== c) x.classList.remove('kb-over'); });
      if (c !== from) c.classList.add('kb-over');
    });
    board.addEventListener('drop', function (e) {
      var c = col(e.target);
      if (!dragged || !c) return;
      e.preventDefault();
      c.classList.remove('kb-over');
      var card = dragged; dragged = null;
      card.classList.remove('kb-dragging');
      if (c === from) return; // poradie v stĺpci sa neukladá
      move(card, c, from, next);
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
