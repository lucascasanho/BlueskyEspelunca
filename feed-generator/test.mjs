import test from 'node:test'
import assert from 'node:assert/strict'

const normalize = (value = '') => String(value).normalize('NFKC').toLocaleLowerCase('pt-BR').replace(/\s+/g, ' ').trim()
const isPtBr = (record) => Array.isArray(record?.langs) && record.langs.map((v) => String(v).toLowerCase()).some((v) => v === 'pt-br')
const blocked = ['nytimes.com', 'estadao.com.br', 't.co']
const isBlockedUrl = (value) => { try { const u = new URL(value); const h = u.hostname.toLowerCase().replace(/^www\./, ''); return blocked.some((d) => h === d || h.endsWith(`.${d}`)) } catch { return true } }

test('PT-BR passa', () => assert.equal(isPtBr({ langs: ['pt-BR'] }), true))
test('PT-PT não passa no modo PT-BR', () => assert.equal(isPtBr({ langs: ['pt-PT'] }), false))
test('pt genérico não passa sem identificação PT-BR', () => assert.equal(isPtBr({ langs: ['pt'] }), false))
test('URL de paywall conhecida é bloqueada', () => assert.equal(isBlockedUrl('https://nytimes.com/foo'), true))
test('redirector conhecido é bloqueado', () => assert.equal(isBlockedUrl('https://t.co/test'), true))
test('URL livre não é bloqueada pela lista', () => assert.equal(isBlockedUrl('https://agenciabrasil.ebc.com.br/teste'), false))
test('normalização preserva texto e ignora caixa', () => assert.equal(normalize('  TECNOLOGIA  '), 'tecnologia'))
