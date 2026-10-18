import { orgLocation, orgMark } from '@/features/organizations/domain/organizations';
import { banco, notaria } from '@/testing/fakes';

describe('organizaciones', () => {
  it('marca con iniciales y ubicación', () => {
    expect(orgMark(notaria.name)).toBe('N1'); expect(orgMark(banco.name)).toBe('BC'); expect(orgMark('Registraduría')).toBe('REG');
    expect(orgLocation(notaria)).toBe('Cra. 13 #54-21 · Bogotá'); expect(orgLocation(banco)).toBe('Quito');
  });
});
